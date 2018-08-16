unit RequestTransport;

interface

uses
  Windows, WinInet, AvL, avlSyncObjs;

type
  PExternalTransportResponce = ^TExternalTransportResponce;
  TExternalTransportResponce = record
    Data: Pointer;
    Length: Integer;
    Free: procedure(P: PExternalTransportResponce); stdcall;
  end;
  TExternalTransportCreate = function: Pointer; stdcall;
  TExternalTransportFree = procedure(Inst: Pointer); stdcall;
  TExternalTransportConnect = function(Inst: Pointer; Server: PChar; Port: Word; UserName, Password: PChar; UseSSL: LongBool): LongBool; stdcall;
  TExternalTransportDisconnect = procedure(Inst: Pointer); stdcall;
  TExternalTransportSendRequest = function(Inst, Data: Pointer; Length: Integer): PExternalTransportResponce; stdcall;
  TRequestTransport = class
  public
    procedure Connect(const Server: string; Port: Word; const UserName, Password: string; UseSSL: Boolean); virtual; abstract;
    procedure Disconnect; virtual; abstract;
    function SendRequest(Sender: TObject; const Request: string): string; virtual; abstract;
  end;
  TWininetRequestTransport = class(TRequestTransport)
  private
    FSession, FConnection: HINTERNET;
    FRequestFlags: Cardinal;
    FRequestLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const Server: string; Port: Word; const UserName, Password: string; UseSSL: Boolean); override;
    procedure Disconnect; override;
    function SendRequest(Sender: TObject; const Request: string): string; override;
  end;
  TExternalRequestTransport = class(TRequestTransport)
  private
    FLib: HMODULE;
    FCreate: TExternalTransportCreate;
    FFree: TExternalTransportFree;
    FConnect: TExternalTransportConnect;
    FDisconnect: TExternalTransportDisconnect;
    FSendRequest: TExternalTransportSendRequest;
    FInstance: Pointer;
  public
    constructor Create(const Lib: string);
    destructor Destroy; override;
    procedure Connect(const Server: string; Port: Word; const UserName, Password: string; UseSSL: Boolean); override;
    procedure Disconnect; override;
    function SendRequest(Sender: TObject; const Request: string): string; override;
  end;

implementation

{ TWininetRequestTransport }

constructor TWininetRequestTransport.Create;
begin
  inherited Create;
  FRequestLock := TCriticalSection.Create;
  FSession := InternetOpen('AriaUI', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  //INTERNET_OPTION_CONNECT_TIMEOUT
  //INTERNET_OPTION_CONNECTED_STATE
end;

destructor TWininetRequestTransport.Destroy;
begin
  Disconnect;
  if Assigned(FSession) then
    InternetCloseHandle(FSession);
  FreeAndNil(FRequestLock);
  inherited;
end;

procedure TWininetRequestTransport.Connect(const Server: string; Port: Word; const UserName, Password: string; UseSSL: Boolean);
begin
  if FSession = nil then
    raise Exception.Create('WinInet not initialized');
  Disconnect;
  FRequestLock.Acquire;
  try
    FConnection := InternetConnect(FSession, PChar(Server), Port, PChar(UserName), PChar(Password), INTERNET_SERVICE_HTTP, INTERNET_FLAG_EXISTING_CONNECT, 0);
    if FConnection = nil then
      raise Exception.Create('Can''t connect to Aria2 server');
    FRequestFlags := INTERNET_FLAG_KEEP_CONNECTION or INTERNET_FLAG_DONT_CACHE or INTERNET_FLAG_NO_COOKIES or INTERNET_FLAG_PRAGMA_NOCACHE or INTERNET_FLAG_RELOAD;
    if UseSSL then
      FRequestFlags := FRequestFlags or INTERNET_FLAG_SECURE{ or INTERNET_FLAG_IGNORE_CERT_CN_INVALID or INTERNET_FLAG_IGNORE_CERT_DATE_INVALID};
  finally
    FRequestLock.Release;
  end;
end;

procedure TWininetRequestTransport.Disconnect;
begin
  FRequestLock.Acquire;
  try
    if Assigned(FConnection) then
      InternetCloseHandle(FConnection);
    FConnection := nil;
  finally
    FRequestLock.Release;
  end;
end;

function TWininetRequestTransport.SendRequest(Sender: TObject; const Request: string): string;
var
  Req: HINTERNET;
  Len, Avail, Read: Cardinal;
begin
  Result := '';
  if FConnection = nil then
    raise Exception.Create('No connection to Aria2 server');
  FRequestLock.Acquire;
  try
    Req := HttpOpenRequest(FConnection, 'POST', '/jsonrpc', nil, nil, nil, FRequestFlags, 0);
    if Req = nil then
      raise Exception.Create('Can''t open request');
    try
      if not HttpSendRequest(Req, PChar('Content-Length: ' + IntToStr(Length(Request))), Cardinal(-1), PChar(Request), Length(Request)) then
        raise Exception.Create('Can''t send request');
      while InternetQueryDataAvailable(Req, Avail, 0, 0) do
      begin
        if Avail = 0 then Break;
        Len := Length(Result);
        SetLength(Result, Len + Avail);
        if not InternetReadFile(Req, @Result[Len + 1], Avail, Read) then Break;
        if Read < Avail then
          SetLength(Result, Length(Result) - Avail + Read);
      end;
    finally
      InternetCloseHandle(Req);
    end;
  finally
    FRequestLock.Release;
  end;
end;

{ TExternalRequestTransport }

constructor TExternalRequestTransport.Create(const Lib: string);
begin
  inherited Create;
  FLib := LoadLibrary(PChar(Lib));
  if FLib = 0 then
    raise Exception.Create('Can''t load library ' + Lib);
  FCreate := GetProcAddress(FLib, 'Create');
  FFree := GetProcAddress(FLib, 'Free');
  FConnect := GetProcAddress(FLib, 'Connect');
  FDisconnect := GetProcAddress(FLib, 'Disconnect');
  FSendRequest := GetProcAddress(FLib, 'SendRequest');
  Assert(Assigned(FCreate) and Assigned(FFree) and Assigned(FConnect) and Assigned(FDisconnect) and Assigned(FSendRequest), 'Invalid transport library');
  FInstance := FCreate();
end;

destructor TExternalRequestTransport.Destroy;
begin
  if Assigned(FFree) and Assigned(FInstance) then
    FFree(FInstance);
  FreeLibrary(FLib);
  inherited;
end;

procedure TExternalRequestTransport.Connect(const Server: string; Port: Word; const UserName, Password: string; UseSSL: Boolean);
begin
  if not FConnect(FInstance, PChar(Server), Port, PChar(UserName), PChar(Password), UseSSL) then
    raise Exception.Create('ExternalTransport.Connect failed');
end;

procedure TExternalRequestTransport.Disconnect;
begin
  FDisconnect(FInstance);
end;

function TExternalRequestTransport.SendRequest(Sender: TObject; const Request: string): string;
var
  Res: PExternalTransportResponce;
begin
  Res := FSendRequest(FInstance, @Request[1], Length(Request));
  if not Assigned(Res) then
    raise Exception.Create('ExternalTransport.SendRequest failed');
  SetLength(Result, Res.Length);
  Move(Res.Data^, Result[1], Res.Length);
  Res.Free(Res); 
end;

end.