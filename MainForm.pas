unit MainForm;

//TODO: Transfers sorting, filtering & searching
//TODO: Uncaught exception on InfoPane tab switching (Files->Info) (problems with file icons on large lists)
//TODO: Heartbeat indicator
//TODO: scroll TransfersList to end

interface

uses
  Windows, CommCtrl, Messages, ShellAPI, AvL, avlUtils, avlSplitter,
  avlTrayIcon, avlJSON, avlEventBus, Utils, Aria2, RequestTransport,
  UpdateThread, TransfersList, InfoPane;

type
  TTransferHandler = function(GID: TAria2GID; Param: Integer): Boolean of object;
  TPerServerStorage = class
  private
    FSection: string;
    FTemporary: TStringList;
    function GetPersistent(const Name: string): string;
    function GetTemporary(const Name: string): TObject;
    procedure PutPersistent(const Name, Value: string);
    procedure PutTemporary(const Name: string; const Value: TObject);
  public
    constructor Create(ServerIndex: Integer);
    destructor Destroy; override;
    property Persistent[const Name: string]: string read GetPersistent write PutPersistent;
    property Temporary[const Name: string]: TObject read GetTemporary write PutTemporary; default;
  end;
  TMainForm = class(TForm)
    MainMenu, TrayMenu, TransfersMenu: TMenu;
    ToolBar: TToolBar;
    StatusBar: TStatusBar;
    Splitter: TSplitter;
    TrayIcon: TAvLTrayIcon; //TODO: check icon re-creation on explorer restart
    ServersList: TComboBoxEx;
    TransfersList: TTransfersList;
    Info: TInfoPane;
  private
    FMinWidth, FMinHeight: Integer;
    FEvLoadSettings, FEvSaveSettings, FEvServerChanged, FEvUpdate: Integer;
    FAccelTable: HAccel;
    FRequestTransport: TRequestTransport;
    FAria2: TAria2;
    FCurServerStorage: TPerServerStorage;
    FUpdateThread: TUpdateThread;
    procedure AddMetalink(Sender: TObject);
    procedure AddTorrent(Sender: TObject);
    procedure AddURL(Sender: TObject);
    function CheckIntegrity(GID: TAria2GID; Param: Integer): Boolean;
    procedure ClearStatusBar;
    function Confirm(ID: Integer; const Message: string): Boolean;
    procedure ExitProgram;
    function FormClose(Sender: TObject): Boolean;
    procedure FormDestroy(Sender: TObject);
    function FormMinimize(Sender: TObject): Boolean;
    procedure FormResize(Sender: TObject);
    procedure TrayIconMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    function QueryEndSession(var Msg: TMessages): Boolean;
    function FormProcessMsg(var Msg: TMsg): Boolean;
    function MoveTransfer(GID: TAria2GID; Param: Integer): Boolean;
    function PauseTransfer(GID: TAria2GID; Param: Integer): Boolean;
    procedure ProcessSelected(ID: Integer; Handler: TTransferHandler; const Messages: array of string; Param: Integer = 0);
    procedure Refresh;
    function RemoveTransfer(GID: TAria2GID; Param: Integer): Boolean;
    procedure RepaintAll;
    function ResumeTransfer(GID: TAria2GID; Param: Integer): Boolean;
    procedure ServerChange(Sender: TObject);
    procedure ShowAbout;
    procedure ShowServerVersion;
    procedure SplitterMove(Sender: TObject);
    procedure TransferDblClick(Sender: TObject);
    function TransferProperties(GID: TAria2GID; Param: Integer): Boolean;
    procedure UpdateKeys;
    procedure WMCommand(var Msg: TWMCommand); message WM_COMMAND;
    procedure WMNotify(var Msg: TWMNotify); message WM_NOTIFY;
    //procedure WMDropFiles(var Msg: TWMDropFiles); message WM_DROPFILES;
    procedure WMSizing(var Msg: TWMMoving); message WM_SIZING;
    procedure WMContextMenu(var Msg: TWMContextMenu); message WM_CONTEXTMENU;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadSettings;
    procedure SaveSettings;
    property Aria2: TAria2 read FAria2;
    property CurServerStorage: TPerServerStorage read FCurServerStorage;
  end;

var
  FormMain: TMainForm;

const
  //Sender: MainForm
  EvLoadSettings = 'MainForm.LoadSettings'; //No params
  EvSaveSettings = 'MainForm.SaveSettings'; //No params
  EvServerChanged = 'MainForm.ServerChanged'; //[PrevServerStorage, CurServerStorage]
  EvUpdate = 'MainForm.Update'; //[UpdateThread]
  AppCaption = 'Aria UI';
  SServers = 'Servers';
  SServer = 'Server.';
  SDisabledDialogs = 'DisabledDialogs'; //TODO
  SDebug = 'Debug';
  SCurrent = 'Current';
  SHost = 'Host';
  SPort = 'Port';
  SUsername = 'Username';
  SPassword = 'Password';
  SToken = 'Token';
  SUseSSL = 'UseSSL';
  SSplitter = 'Splitter';

implementation

uses
  OptionsForm, AddForm, ServerOptionsForm, RPCRequestForm;

type
  TTBButtons = (tbAddURL, tbAddTorrent, tbAddMetalink, tbResume, tbPause, tbRemove, tbMoveUp, tbMoveDown, tbOptions, tbExit);
  TSBPart = (sbConnection, sbDownSpeed, sbUpSpeed, sbStats);
  TMenuID = (IDMenuFile = 1000, IDAddURL, IDAddTorrent, IDAddMetalink, IDOptions, IDFileSep0, IDExit,
             IDMenuTransfers = 2000, IDResume, IDPause, IDRemove, IDProperties, IDCheckIntegrity, IDTransfersSep0, IDMoveUp, IDMoveDown, IDTransfersSep1, IDResumeAll, IDPauseAll, IDPurge, IDTransferSep2, IDFind, IDFindNext,
             IDMenuServer = 3000, IDServerOptions, IDServerVersion, IDSaveSession, IDShutdownServer, IDRPCRequest,
             IDMenuHelp = 5000, IDAriaWebpage, IDAriaDocs, IDHelpSep0, IDAbout,
             IDMenuTray = 10000, IDTrayShow, IDTraySep0, IDTrayResumeAll, IDTrayPauseAll, IDTrayPurge, IDTraySep1, IDTrayOptions, IDTrayAbout, IDTraySep2, IDTrayExit);

const
  CRLF = #13#10;
  AboutIcon = 'MAINICON';
  AboutCaption = 'About ';
  AboutText = 'Aria UI 1.0 alpha'+CRLF+CRLF+
              'Copyright '#169' VgaSoft, 2017-2018'+CRLF+
              'vgasoft@gmail.com';
  MenuFileCapt = '&File';
  MenuFile: array[0..6] of PChar = ('1001',
    'Add &URL...'#9'Ctrl-U',
    'Add &Torrent...'#9'Ctrl-O',
    'Add &Metalink...'#9'Ctrl-M',
    'Op&tions...',
    '-',
    'E&xit'#9'Alt-X');
  MenuTransfersCapt = '&Transfers';
  MenuTransfers: array[0..15] of PChar = ('2001',
    '&Resume'#9'Ctrl-R', //TODO: restarting of failed transfers
    '&Pause'#9'Ctrl-P',
    'R&emove'#9'Del',
    'Pr&operties...'#9'Alt-Enter',
    'Check &integrity',
    '-',
    'Move &up'#9'Ctrl-Up',
    'Move &down'#9'Ctrl-Down',
    '-',
    'Res&ume all',
    'Pau&se all',
    'Purge &completed'#9'F4',
    '-',
    '&Find...'#9'Ctrl-F',
    'Find &next'#9'F3');
  MenuServerCapt = '&Server';
  MenuServer: array[0..5] of PChar = ('3001',
    'Server &options...'#9'F11',
    'Server &version...',
    '&Save session',
    'Shut&down server'#9'F12',
    '&RPC Request...');
  MenuHelpCapt = '&Help';
  MenuHelp: array[0..4] of PChar = ('5001',
    'Aria2 &web page...',
    'Aria2 &documentation...',
    '-',
    '&About...'#9'F1');
  MenuTray: array[0..10] of PChar = ('10001',
    '&Show',
    '-',
    '&Resume all',
    '&Pause all',
    'Purge &completed',
    '-',
    '&Options...',
    '&About...',
    '-',
    'E&xit');
  TBButtons: array[0..12] of record Caption: string; ImageIndex: Integer; end = (
    (Caption: 'Add URL...'; ImageIndex: 0),
    (Caption: 'Add Torrent...'; ImageIndex: 1),
    (Caption: 'Add Metalink...'; ImageIndex: 2),
    (Caption: '-'; ImageIndex: -1),
    (Caption: 'Resume'; ImageIndex: 3),
    (Caption: 'Pause'; ImageIndex: 4),
    (Caption: 'Remove'; ImageIndex: 5),
    (Caption: '-'; ImageIndex: -1),
    (Caption: 'Move up'; ImageIndex: 6),
    (Caption: 'Move down'; ImageIndex: 7),
    (Caption: '-'; ImageIndex: -1),
    (Caption: 'Options...'; ImageIndex: 8),
    (Caption: 'Exit'; ImageIndex: 9));
  TBMenuIDs: array[TTBButtons] of TMenuID = (IDAddURL, IDAddTorrent, IDAddMetalink, IDResume, IDPause, IDRemove, IDMoveUp, IDMoveDown, IDOptions, IDExit);
  SBParts: array[TSBPart] of Integer = (100, 250, 400, -1);

var
  Accels: array[0..16] of TAccel = ( //TODO: More accels
    (fVirt: FCONTROL or FVIRTKEY; Key: Ord('U'); Cmd: Ord(IDAddURL)),
    (fVirt: FCONTROL or FVIRTKEY; Key: Ord('O'); Cmd: Ord(IDAddTorrent)),
    (fVirt: FCONTROL or FVIRTKEY; Key: Ord('M'); Cmd: Ord(IDAddMetalink)),
    (fVirt: FALT or FVIRTKEY; Key: Ord('X'); Cmd: Ord(IDExit)),
    (fVirt: FCONTROL or FVIRTKEY; Key: Ord('R'); Cmd: Ord(IDResume)),
    (fVirt: FCONTROL or FVIRTKEY; Key: Ord('P'); Cmd: Ord(IDPause)),
    (fVirt: FCONTROL or FSHIFT or FVIRTKEY; Key: Ord('P'); Cmd: Ord(IDPause)),
    //(fVirt: FVIRTKEY; Key: VK_DELETE; Cmd: Ord(IDRemove)), //TODO: no such keys in accelerators, move to TransfersList.OnKeyDown
    //(fVirt: FSHIFT or FVIRTKEY; Key: VK_DELETE; Cmd: Ord(IDRemove)), 
    (fVirt: FALT or FVIRTKEY; Key: VK_RETURN; Cmd: Ord(IDProperties)), //TODO: RALT too!
    (fVirt: FCONTROL or FVIRTKEY; Key: VK_UP; Cmd: Ord(IDMoveUp)),
    (fVirt: FCONTROL or FVIRTKEY; Key: VK_DOWN; Cmd: Ord(IDMoveDown)),
    (fVirt: FCONTROL or FVIRTKEY; Key: Ord('F'); Cmd: Ord(IDFind)),
    (fVirt: FVIRTKEY; Key: VK_F3; Cmd: Ord(IDFindNext)),
    (fVirt: FVIRTKEY; Key: VK_F4; Cmd: Ord(IDPurge)),
    (fVirt: FVIRTKEY; Key: VK_F11; Cmd: Ord(IDServerOptions)),
    (fVirt: FVIRTKEY; Key: VK_F12; Cmd: Ord(IDShutdownServer)),
    (fVirt: FSHIFT or FVIRTKEY; Key: VK_F12; Cmd: Ord(IDShutdownServer)),
    (fVirt: FVIRTKEY; Key: VK_F1; Cmd: Ord(IDAbout)));

constructor TMainForm.Create;

  procedure AddMenu(const Name: string; ID: Cardinal; const Template: array of PChar);
  var
    Menu: TMenu;
  begin
    Menu := TMenu.Create(Self, false, Template);
    InsertMenu(MainMenu.Handle, ID, MF_BYCOMMAND or MF_POPUP, Menu.Handle, PChar(Name));
  end;

var
  i: Integer;
begin
  inherited Create(nil, AppCaption);
  //TODO: Detect first run and run first start wizard
  FEvLoadSettings := EventBus.RegisterEvent(EvLoadSettings);
  FEvSaveSettings := EventBus.RegisterEvent(EvSaveSettings);
  FEvServerChanged := EventBus.RegisterEvent(EvServerChanged);
  FEvUpdate := EventBus.RegisterEvent(EvUpdate);
  OnDestroy := FormDestroy;
  OnClose := FormClose;
  OnMinimize := FormMinimize;
  OnProcessMsg := FormProcessMsg;
  SetSize(800, 600);
  Position := poScreenCenter;
  FMinHeight := 300;
  FMinWidth := 400;
  Settings.RestoreFormState(ClassName, Self);
  FRequestTransport := TRequestTransport.Create;
  FAria2 := TAria2.Create(FRequestTransport.SendRequest);
  FUpdateThread := TUpdateThread.Create(FAria2);
  FUpdateThread.BeforeUpdate := UpdateKeys;
  FUpdateThread.OnUpdate := Refresh;
  MainMenu := TMenu.Create(Self, true, ['0']);
  AddMenu(MenuFileCapt, Ord(IDMenuFile), MenuFile);
  AddMenu(MenuTransfersCapt, Ord(IDMenuTransfers), MenuTransfers);
  AddMenu(MenuServerCapt, Ord(IDMenuServer), MenuServer);
  AddMenu(MenuHelpCapt, Ord(IDMenuHelp), MenuHelp);
  SetMenu(Handle, MainMenu.Handle);
  TrayMenu := TMenu.Create(Self, false, MenuTray);
  TransfersMenu := TMenu.Create(Self, false, MenuTransfers);
  TrayIcon := TAvLTrayIcon.Create;
  TrayIcon.ToolTip := Caption;
  TrayIcon.Icon := LoadImage(hInstance, 'MAINICON', IMAGE_ICON, 16, 16, LR_SHARED);
  TrayIcon.OnQueryEndSession := QueryEndSession;
  TrayIcon.OnMouseDown := TrayIconMouseDown;
  TrayIcon.Active := true;
  FAccelTable := CreateAcceleratorTable(Accels[0], Length(Accels));
  ServersList := TComboBoxEx.Create(Self, csDropDownList);
  ServersList.Hint := 'Select server';
  ServersList.OnChange := ServerChange;
  ToolBar := TToolBar.Create(Self, true);
  ToolBar.Style := ToolBar.Style or TBSTYLE_TOOLTIPS or CCS_TOP;
  ToolBar.ExStyle := ToolBar.ExStyle or TBSTYLE_EX_MIXEDBUTTONS;
  ToolBar.Perform(TB_SETMAXTEXTROWS, 0, 0);
  ToolBar.Perform(TB_AUTOSIZE, 0, 0);
  Toolbar.Indent := 120;
  ToolBar.Images := LoadImageList('TBMAIN');
  for i := Low(TBButtons) to High(TBButtons) do
    ToolBar.ButtonAdd(TBButtons[i].Caption, TBButtons[i].ImageIndex);
  ServersList.SetBounds(ToolBar.Left + 2, ToolBar.Top + (ToolBar.Height - ServersList.Height) div 2, ToolBar.Indent - 4, ServersList.Height);
  StatusBar := TStatusBar.Create(Self, '');
  StatusBar.SetParts(Length(SBParts), SBParts);
  Splitter := TSplitter.Create(Self, false);
  Splitter.SetBounds(0, Settings.ReadInteger(ClassName, SSplitter, 300), ClientWidth, Splitter.Height);
  Splitter.OnMove := SplitterMove;
  TransfersList := TTransfersList.Create(Self);
  TransfersList.SetBounds(0, ToolBar.Height, ClientWidth, Splitter.Top - ToolBar.Height);
  TransfersList.OnDblClick := TransferDblClick; //TODO: OnKeyDown and move some hotkays (and add Ctrl-A)
  Info := TInfoPane.Create(Self);
  Info.SetBounds(0, Splitter.Bottom, ClientWidth, StatusBar.Top - Splitter.Bottom);
  //DragAcceptFiles(Handle, true);
  OnResize := FormResize;
  FormResize(Self);
  LoadSettings;
  FUpdateThread.Resume;
end;

destructor TMainForm.Destroy;
begin
  FreeAndNil(FUpdateThread);
  FreeAndNil(FAria2);
  FreeAndNil(FRequestTransport);
  DestroyAcceleratorTable(FAccelTable);
  FreeAndNil(TrayIcon);
  FreeAndNil(MainMenu);
  FreeAndNil(TrayMenu);
  FreeAndNil(TransfersMenu);
  ToolBar.Images.Free;
  inherited;
end;

procedure TMainForm.TrayIconMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    if Visible then
      Hide
    else
      Show
  else begin
    SetForegroundWindow(Handle);
    TrayMenu.Popup(X, Y);
    Perform(WM_NULL, 0, 0);
  end;
end;

function TMainForm.QueryEndSession(var Msg: TMessages): Boolean;
begin
  Msg.Result := 1;
  ExitProgram;
  Result := true;
end;

procedure TMainForm.ShowAbout;
var
  Version: TOSVersionInfo;
  MsgBoxParamsW: TMsgBoxParamsW;
  MsgBoxParamsA: TMsgBoxParamsA;
begin
  Version.dwOSVersionInfoSize := SizeOf(TOSVersionInfo);
  GetVersionEx(Version);
  if Version.dwPlatformId = VER_PLATFORM_WIN32_NT then
  begin
    FillChar(MsgBoxParamsW, SizeOf(MsgBoxParamsW), #0);
    with MsgBoxParamsW do
    begin
      cbSize := SizeOf(MsgBoxParamsW);
      hwndOwner := Handle;
      hInstance := SysInit.hInstance;
      lpszText  := PWideChar(WideString(AboutText));
      lpszCaption := PWideChar(WideString(AboutCaption + Caption));
      lpszIcon := AboutIcon;
      dwStyle := MB_USERICON;
    end;
    MessageBoxIndirectW(MsgBoxParamsW);
  end
  else begin
    FillChar(MsgBoxParamsA, SizeOf(MsgBoxParamsA), #0);
    with MsgBoxParamsA do
    begin
      cbSize := SizeOf(MsgBoxParamsA);
      hwndOwner := Handle;
      hInstance := SysInit.hInstance;
      lpszText  := PAnsiChar(AboutText);
      lpszCaption := PAnsiChar(AboutCaption + Caption);
      lpszIcon := AboutIcon;
      dwStyle := MB_USERICON;
    end;
    MessageBoxIndirectA(MsgBoxParamsA);
  end;
end;

procedure TMainForm.ShowServerVersion;
const
  Term: array[Boolean] of string = (', ', ')');
var
  i: Integer;
  Ver: TAria2Struct;
  S: string;
begin
  with FAria2 do
    Ver := GetStruct(GetVersion);
  try
    S := 'Aria2 ' + Ver[sfVersion] + ' (features: ';
    Ver.Root := sfEnabledFeatures;
    for i := 0 to Ver.Length[''] - 1 do
      S := S + Ver[IntToStr(i)] + Term[i = Ver.Length[''] - 1];
    MessageDlg(S, 'Server version', MB_ICONINFORMATION);
  finally
    Ver.Free;
  end;
end;

procedure TMainForm.SplitterMove(Sender: TObject);
begin
  TransfersList.SetBounds(Splitter.Left, ToolBar.Height, Splitter.Width, Splitter.Top - ToolBar.Height);
  Info.SetBounds(Splitter.Left, Splitter.Bottom, Splitter.Width, StatusBar.Top - Splitter.Bottom);
end;

procedure TMainForm.WMCommand(var Msg: TWMCommand);
var
  S: string;
begin
  if (Msg.Ctl = 0) and (Msg.NotifyCode in [0, 1]) then
    try
      case TMenuID(Msg.ItemID) of
        IDExit, IDTrayExit: ExitProgram;
        IDTrayShow: if Visible then Hide else Show;
        IDOptions, IDTrayOptions: begin SaveSettings; FormOptions.Show; end;
        IDAddURL: FormAdd.Show('Add URL', '', false, AddURL);
        IDAddTorrent: FormAdd.Show('Add Torrent', 'Torrent files|*.torrent|All files|*.*', true, AddTorrent);
        IDAddMetalink: FormAdd.Show('Add Metalink', 'Metalink files|*.metalink;*.meta4|All files|*.*', true, AddMetalink);
        IDResume: ProcessSelected(Ord(IDResume), ResumeTransfer, []);
        IDPause: ProcessSelected(Ord(IDPause), PauseTransfer, [], Integer(LongBool(GetKeyState(VK_SHIFT) < 0)));
        IDRemove: ProcessSelected(Ord(IDRemove), RemoveTransfer, ['Remove transfer "%s"?', 'Remove %d selected transfers?'], Integer(LongBool(GetKeyState(VK_SHIFT) < 0)));
        IDProperties: TransferProperties(TransfersList.GID[TransfersList.SelectedIndex], 0);
        IDCheckIntegrity: ProcessSelected(Ord(IDCheckIntegrity), CheckIntegrity, [], 0);
        IDMoveDown: ProcessSelected(Ord(IDMoveDown), MoveTransfer, [], 1);
        IDMoveUp: ProcessSelected(Ord(IDMoveUp), MoveTransfer, [], -1);
        IDResumeAll, IDTrayResumeAll: with FAria2 do CheckResult(UnpauseAll);
        IDPauseAll, IDTrayPauseAll: with FAria2 do CheckResult(PauseAll(GetKeyState(VK_SHIFT) < 0));
        IDPurge: if Confirm(Ord(IDPurge), 'Purge completed & removed transfers?') then with FAria2 do CheckResult(PurgeDownloadResult);
        IDTrayPurge: with FAria2 do CheckResult(PurgeDownloadResult);
        IDFind: if InputQuery(Handle, 'Find transfer', 'Search mask:', S) then TransfersList.Find(S);
        IDFindNext: TransfersList.Find('');
        IDServerOptions: FormServerOptions.Show;
        IDServerVersion: ShowServerVersion;
        IDSaveSession: with FAria2 do if GetBool(SaveSession) then ShowMessage('Session saved');
        IDShutdownServer: if Confirm(Ord(IDShutdownServer), 'Shutdown server?') then with FAria2 do CheckResult(Shutdown(GetKeyState(VK_SHIFT) < 0));
        IDRPCRequest: FormRPCRequest.ShowModal;
        IDAriaWebpage: Execute('http://aria2.github.io');
        IDAriaDocs: Execute('http://aria2.github.io/manual/en/html/index.html');
        IDAbout, IDTrayAbout: ShowAbout;
      end;
    except
      on E: Exception do ShowException;
    end;
  if Assigned(ToolBar) and (Msg.Ctl = ToolBar.Handle) then
    Perform(WM_COMMAND, Ord(TBMenuIDs[TTBButtons(Msg.ItemID)]), 0);
end;

{procedure TMainForm.WMDropFiles(var Msg: TWMDropFiles);
var
  FileName: array[0..MAX_PATH] of Char;
  i: Integer;
begin
  for i := 0 to DragQueryFile(Msg.Drop, $FFFFFFFF, nil, 0) - 1 do
  begin
    DragQueryFile(Msg.Drop, i, FileName, MAX_PATH + 1);
    //Process file here
  end;
  DragFinish(Msg.Drop);
end;}

procedure TMainForm.FormResize(Sender: TObject);
begin
  ToolBar.Perform(TB_AUTOSIZE, 0, 0);
  StatusBar.Perform(WM_SIZE, 0, 0);
  if (ClientWidth <= 0) or (ClientHeight <= 0) then Exit;
  Splitter.Width := ClientWidth;
  Splitter.Top := StatusBar.Top - Info.Height - Splitter.Height;
  Splitter.MinPos := ToolBar.Height + 70;
  Splitter.MaxPos := StatusBar.Top - Splitter.Height;
  SplitterMove(Splitter);
  RepaintAll;
end;

procedure TMainForm.WMSizing(var Msg: TWMMoving);
begin
  with Msg do
  begin
    if DragRect.Right - DragRect.Left < FMinWidth then
      if (Edge = WMSZ_LEFT) or (Edge = WMSZ_TOPLEFT) or (Edge = WMSZ_BOTTOMLEFT)
        then DragRect.Left := DragRect.Right - FMinWidth
        else DragRect.Right := DragRect.Left + FMinWidth;
    if DragRect.Bottom - DragRect.Top < FMinHeight then
      if (Edge = WMSZ_TOP) or (Edge = WMSZ_TOPLEFT) or (Edge = WMSZ_TOPRIGHT)
        then DragRect.Top := DragRect.Bottom - FMinHeight
        else DragRect.Bottom := DragRect.Top + FMinHeight;
  end;
end;

procedure TMainForm.RepaintAll;
var
  Cur: TWinControl;
begin
  Cur := NextControl;
  while Assigned(Cur) do
  begin
    Cur.Invalidate;
    UpdateWindow(Cur.Handle);
    Cur := Cur.NextControl;
  end;
end;

procedure TMainForm.AddMetalink(Sender: TObject);
begin
  try
    with FAria2 do
      CheckResult(AddMetalink(LoadFile(FormAdd.FileName.Text), FormAdd.Options));
  except
    on E: Exception do ShowException;
  end;
end;

procedure TMainForm.AddTorrent(Sender: TObject);
begin
  try
    with FAria2 do
      CheckResult(AddTorrent(LoadFile(FormAdd.FileName.Text), [], FormAdd.Options));
  except
    on E: Exception do ShowException;
  end;
end;

procedure TMainForm.AddURL(Sender: TObject);
begin
  try
    with FAria2 do
      CheckResult(AddUri(FormAdd.URLs, FormAdd.Options)); //TODO: Async CheckResult
  except
    on E: Exception do ShowException;
  end;
end;

function TMainForm.CheckIntegrity(GID: TAria2GID; Param: Integer): Boolean;
const
  Options: array[0..1] of TAria2Option = ((Key: soBTSeedUnverified; Value: svFalse), (Key: soCheckIntegrity; Value: svTrue));
begin
  with FAria2 do
    Result := GetBool(ChangeOptions(GID, Options)); //TODO: Revert options on completion
end;

procedure TMainForm.ClearStatusBar;
var
  i: Integer;
begin
  for i := Ord(Low(SBParts)) to Ord(High(SBParts)) do
    StatusBar.SetPartText(i, 0, '');
end;

function TMainForm.Confirm(ID: Integer; const Message: string): Boolean;
begin
  Result := Settings.ReadBool(SDisabledDialogs, IntToStr(ID), false) or (MessageDlg(Message, Caption, MB_ICONQUESTION or MB_YESNO) = ID_YES);
end;

procedure TMainForm.ExitProgram;
begin
  if Visible then Hide;
  Close;
end;

function TMainForm.FormClose(Sender: TObject): Boolean;
begin
  Result := not Visible;
  if Visible then
    Hide
  else
    SaveSettings;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FUpdateThread.Terminate;
  FUpdateThread.WaitFor;
end;

function TMainForm.FormMinimize(Sender: TObject): Boolean;
begin
  Result := false;
  Hide;
end;

function TMainForm.FormProcessMsg(var Msg: TMsg): Boolean;
begin
  Result := TranslateAccelerator(Handle, FAccelTable, Msg) <> 0;
end;

procedure TMainForm.LoadSettings;
var
  i: Integer;
begin
  FCurServerStorage := nil;
  for i := 0 to ServersList.ItemCount - 1 do
    ServersList.Objects[i].Free;
  ServersList.Clear;
  for i := 0 to Settings.ReadInteger(SServers, SCount, 0) - 1 do
    ServersList.Objects[ServersList.ItemAdd(Settings.ReadString(SServers, IntToStr(i), '###'))] := TPerServerStorage.Create(i);
  if ServersList.ItemCount = 0 then
    ServersList.Objects[ServersList.ItemAdd('###')] := TPerServerStorage.Create(0);
  ServersList.ItemIndex := Settings.ReadInteger(SServers, SCurrent, 0);
  EventBus.SendEvent(FEvLoadSettings, Self, []);
  RepaintAll;
  ServerChange(ServersList);
end;

function TMainForm.MoveTransfer(GID: TAria2GID; Param: Integer): Boolean;
begin
  Result := true;
  with FAria2 do
    CheckResult(ChangePosition(GID, Param, poFromCurrent));
end;

function TMainForm.PauseTransfer(GID: TAria2GID; Param: Integer): Boolean;
begin
  with FAria2 do //TODO: set options like pause/pause-metadata
    Result := GetGID(Pause(GID, LongBool(Param))) = GID;
end;

procedure TMainForm.ProcessSelected(ID: Integer; Handler: TTransferHandler; const Messages: array of string; Param: Integer = 0);
var
  i: Integer;
begin
  if TransfersList.SelCount = 0 then Exit //TODO: collect gids before, clear selection after (anly when deleting, maybe?)
  else if TransfersList.SelCount = 1 then
  begin
    if (Length(Messages) > 0) and not Confirm(ID, Format(Messages[0], [TransfersList.SelectedCaption])) then Exit;
    Handler(TransfersList.GID[TransfersList.SelectedIndex], Param);
  end
  else begin
    if (Length(Messages) > 1) and not Confirm(ID, Format(Messages[1], [TransfersList.SelCount])) then Exit;
    for i := 0 to TransfersList.SelCount - 1 do
      Handler(TransfersList.GID[TransfersList.Selected[i]], Param);
  end;
end;

procedure TMainForm.Refresh;
begin
  try
    if Assigned(FUpdateThread.Stats) then
    begin
      with FUpdateThread do
        TrayIcon.ToolTip := Format('%s' + CRLF + 'Active: %d; Waiting: %d; Stopped: %d' + CRLF + 'Down: %s/s; Up: %s/s',
          [Caption, Stats.Int[sfNumActive], Stats.Int[sfNumWaiting], Stats.Int[sfNumStopped], SizeToStr(Stats.Int[sfDownloadSpeed]), SizeToStr(Stats.Int[sfUploadSpeed])]);
      if Visible then
      try //TODO: Request details only for visible items
        StatusBar.SetPartText(Ord(sbConnection), 0, 'OK');
        TransfersList.BeginUpdate;
        with FUpdateThread do
        begin
          if Assigned(Active) then
            TransfersList.Update(Active, Names);
          if Assigned(Waiting) then
            TransfersList.Update(Waiting, Names);
          if Assigned(Stopped) then
            TransfersList.Update(Stopped, Names);
          StatusBar.SetPartText(Ord(sbDownSpeed), 0, 'Down: ' + SizeToStr(Stats.Int[sfDownloadSpeed]) + '/s');
          StatusBar.SetPartText(Ord(sbUpSpeed), 0, 'Up: ' + SizeToStr(Stats.Int[sfUploadSpeed]) + '/s');
          StatusBar.SetPartText(Ord(sbStats), 0, Format('Active: %d; Waiting: %d; Stopped: %d', [Stats.Int[sfNumActive], Stats.Int[sfNumWaiting], Stats.Int[sfNumStopped]]));
        end;
        Info.Update(FUpdateThread);
      finally
        TransfersList.EndUpdate;
      end;
    end
    else
    begin
      ClearStatusBar;
      StatusBar.SetPartText(Ord(sbConnection), 0, 'No connection');
      TrayIcon.ToolTip := Caption + CRLF + 'No connection';
    end;
    EventBus.SendEvent(FEvUpdate, Self, [FUpdateThread]);
  except
  end;
end;

function TMainForm.RemoveTransfer(GID: TAria2GID; Param: Integer): Boolean;
var
  Status: TAria2Struct;
begin
  with FAria2 do
  begin
    Status := GetStruct(TellStatus(GID, [sfStatus])); //TODO: it's slow!
    if TAria2Status(StrToEnum(Status[sfStatus], sfStatusValues)) in [asActive, asWaiting, asPaused] then
      Result := GetGID(Remove(GID, LongBool(Param))) = GID
    else
      Result := GetBool(RemoveDownloadResult(GID));
  end;
end;

function TMainForm.ResumeTransfer(GID: TAria2GID; Param: Integer): Boolean;
begin
  with FAria2 do
    Result := GetGID(Unpause(GID)) = GID;
end;

procedure TMainForm.SaveSettings;
begin
  Settings.SaveFormState(ClassName, Self);
  Settings.WriteInteger(ClassName, SSplitter, Splitter.Top);
  EventBus.SendEvent(FEvSaveSettings, Self, []);
end;

procedure TMainForm.ServerChange(Sender: TObject);
var
  Section: string;
  OldStorage: TPerServerStorage;
begin
  OldStorage := FCurServerStorage;
  FCurServerStorage := ServersList.Objects[ServersList.ItemIndex] as TPerServerStorage;
  Section := SServer + IntToStr(ServersList.ItemIndex);
  Settings.WriteInteger(SServers, SCurrent, ServersList.ItemIndex);
  FRequestTransport.Disconnect;
  FAria2.RPCSecret := Settings.ReadString(Section, SToken, '');
  TransfersList.Clear;
  ClearStatusBar;
  StatusBar.SetPartText(Ord(sbConnection), 0, 'Connecting...');
  TrayIcon.ToolTip := Caption;
  FRequestTransport.Connect(Settings.ReadString(Section, SHost, 'localhost'), Settings.ReadInteger(Section, SPort, 6800), Settings.ReadString(Section, SUsername, ''), Settings.ReadString(Section, SPassword, ''), Settings.ReadBool(Section, SUseSSL, false));
  EventBus.SendEvent(FEvServerChanged, Self, [OldStorage, FCurServerStorage]);
end;

function TMainForm.TransferProperties(GID: TAria2GID; Param: Integer): Boolean;
var
  Status: TAria2Struct;
begin
  Result := true;
  with FAria2 do
    Status := GetStruct(TellStatus(GID, []));
  ShowMessage(JsonToStr(Status.Raw));
  Status.Free;
end;

procedure TMainForm.UpdateKeys;
begin
  FUpdateThread.StatsOnly := not Visible;
  FUpdateThread.InfoGID := Info.GID;
  FUpdateThread.InfoKeys := Info.UpdateKeys;
  FUpdateThread.TransferKeys := TransfersList.UpdateKeys;
end;

procedure TMainForm.WMContextMenu(var Msg: TWMContextMenu);
begin
  if Assigned(TransfersList) and (Msg.hWnd = TransfersList.Handle) then
    TransfersMenu.Popup(Msg.XPos, Msg.YPos);
end;

procedure TMainForm.WMNotify(var Msg: TWMNotify);
begin
  inherited;
  if Assigned(TransfersList) and (PNMHdr(Msg.NMHdr).hwndFrom = TransfersList.Handle) then
    if (Msg.NMHdr.code = LVN_ITEMCHANGED) and (PNMListView(Msg.NMHdr).uChanged and LVIF_STATE <> 0) and (PNMListView(Msg.NMHdr).uNewState and LVIS_SELECTED <> 0) then
      Info.GID := TransfersList.GID[PNMListView(Msg.NMHdr).iItem];
end;

procedure TMainForm.TransferDblClick(Sender: TObject);
var
  Status: TAria2Struct;
  Dir: string;
begin
  //TODO: setting "transfer dblclick action"
  if TransfersList.SelectedIndex < 0 then Exit;
  try
    with FAria2 do
      Status := GetStruct(TellStatus(GetGID(TransfersList.SelectedIndex), [sfDir]));
    try
      Dir := StringReplace(Status[sfDir], '/', '\', [rfReplaceAll]);
      if DirectoryExists(Dir) then
        Execute(Dir)
      else
        raise Exception.Create('Directory "' + Dir + '" not found');
    finally
      FreeAndNil(Status);
    end;
  except
    on E: Exception do ShowException;
  end;
end;

{ TPerServerStorage }

constructor TPerServerStorage.Create(ServerIndex: Integer);
begin
  inherited Create;
  FSection := SServer + IntToStr(ServerIndex);
  FTemporary := TStringList.Create;
end;

destructor TPerServerStorage.Destroy;
var
  i: Integer;
begin
  for i := 0 to FTemporary.Count - 1 do
    FTemporary.Objects[i].Free;
  FreeAndNil(FTemporary);
  inherited;
end;

function TPerServerStorage.GetPersistent(const Name: string): string;
begin
  if Assigned(Self) then
    Result := Settings.ReadString(FSection, Name, '')
  else
    Result := '';
end;

function TPerServerStorage.GetTemporary(const Name: string): TObject;
begin
  if Assigned(Self) then
    Result := FTemporary.Objects[FTemporary.IndexOf(Name)]
  else
    Result := nil;
end;

procedure TPerServerStorage.PutPersistent(const Name, Value: string);
begin
  if Assigned(Self) then
    Settings.WriteString(FSection, Name, Value);
end;

procedure TPerServerStorage.PutTemporary(const Name: string; const Value: TObject);
begin
  if not Assigned(Self) then
  begin
    Value.Free;
    Exit;
  end;
  if FTemporary.IndexOf(Name) >= 0 then
    FTemporary.Objects[FTemporary.IndexOf(Name)].Free
  else
    FTemporary.Add(Name);
  FTemporary.Objects[FTemporary.IndexOf(Name)] := Value;
end;

end.
