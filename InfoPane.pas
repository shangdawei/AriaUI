unit InfoPane;

interface

uses
  Windows, Messages, AvL, Aria2, UpdateThread;

type
  TInfoPane = class;
  TInfoPage = class(TSimplePanel)
  protected
    FGID: TAria2GID;
    FParent: TInfoPane;
    FUpdateKeys: TStringArray;
    function GetName: string; virtual; abstract;
    function GetUpdateKeys: TStringArray; virtual;
    procedure SetGID(Value: TAria2GID); virtual;
  public
    constructor Create(Parent: TInfoPane); virtual;
    destructor Destroy; override;
    procedure Update(UpdateThread: TUpdateThread); virtual; abstract;
    procedure LoadSettings; virtual;
    procedure SaveSettings; virtual;
    property Name: string read GetName;
    property GID: TAria2GID read FGID write SetGID;
    property UpdateKeys: TStringArray read GetUpdateKeys;
  end;
  TInfoPane = class(TSimplePanel)
    Tabs: TTabControl;
    Pages: array of TInfoPage;
  private
    FCurPage: TInfoPage;
    procedure Resize(Sender: TObject);
    function GetUpdateKeys: TStringArray;
    function GetGID: TAria2GID;
    procedure SetGID(const Value: TAria2GID);
    procedure WMNotify(var Msg: TWMNotify); message WM_NOTIFY;
  public
    constructor Create(AParent: TWinControl);
    procedure LoadSettings;
    procedure Update(UpdateThread: TUpdateThread);
    procedure SaveSettings;
    property GID: TAria2GID read GetGID write SetGID;
    property UpdateKeys: TStringArray read GetUpdateKeys;
  end;

implementation

uses
  PageInfo, PageFiles;

type
  TInfoPageClass = class of TInfoPage;

const
  InfoPages: array[0..1] of TInfoPageClass = (TPageInfo, TPageFiles);

{ TInfoPane }

constructor TInfoPane.Create(AParent: TWinControl);
var
  Page: Integer;
begin
  inherited Create(AParent, '');
  Border := 2;
  ExStyle := 0;
  Tabs := TTabControl.Create(Self);
  Tabs.Style := tsTabs;
  Tabs.SetPosition(0, 0);
  SetLength(Pages, Length(InfoPages));
  for Page := Low(InfoPages) to High(InfoPages) do
  begin
    Pages[Page] := InfoPages[Page].Create(Self);
    Pages[Page].BringToFront;
    Pages[Page].Visible := false;
    Tabs.TabAdd(Pages[Page].Name);
  end;
  FCurPage := Pages[0];
  FCurPage.Visible := true;
  Tabs.TabIndex := 0;
  OnResize := Resize;
end;

function TInfoPane.GetGID: TAria2GID;
begin
  Result := FCurPage.GID;
end;

function TInfoPane.GetUpdateKeys: TStringArray;
begin
  Result := FCurPage.UpdateKeys;
end;

procedure TInfoPane.LoadSettings;
var
  Page: Integer;
begin
  for Page := 0 to High(Pages) do
    Pages[Page].LoadSettings;
end;

procedure TInfoPane.Resize(Sender: TObject);
var
  Rect: TRect;
  Page: Integer;
begin
  Tabs.SetSize(ClientWidth, ClientHeight);
  Rect.Left := 0;
  Rect.Top := 0;
  Rect.Right := Tabs.ClientWidth;
  Rect.Bottom := Tabs.ClientHeight;
  Tabs.Perform(TCM_ADJUSTRECT, 0, Integer(@Rect));
  for Page := 0 to High(Pages) do
    Pages[Page].SetBounds(Rect.Left, Rect.Top, Rect.Right - Rect.Left, Rect.Bottom - Rect.Top);
end;

procedure TInfoPane.SaveSettings;
var
  i: Integer;
begin
  for i := 0 to High(Pages) do
    Pages[i].SaveSettings;
end;

procedure TInfoPane.SetGID(const Value: TAria2GID);
begin
  FCurPage.GID := Value;
end;

procedure TInfoPane.Update(UpdateThread: TUpdateThread);
begin
  if Assigned(UpdateThread.Stats) and not Assigned(UpdateThread.Info) then
    GID := '';
  FCurPage.Update(UpdateThread);
end;

procedure TInfoPane.WMNotify(var Msg: TWMNotify);
var
  GID: TAria2GID;
begin
  if Assigned(Tabs) and (Msg.NMHdr.hwndFrom = Tabs.Handle) and (Msg.NMHdr.code = TCN_SELCHANGE) then
  begin
    GID := FCurPage.GID;
    FCurPage.Visible := false;
    FCurPage := Pages[Tabs.TabIndex];
    FCurPage.GID := GID;
    FCurPage.Visible := true;
  end;
end;

{ TInfoPage }

constructor TInfoPage.Create(Parent: TInfoPane);
begin
  inherited Create(Parent, '');
  FParent := Parent;
  Border := 2;
  ExStyle := 0;
end;

destructor TInfoPage.Destroy;
begin
  Finalize(FUpdateKeys);
  inherited;
end;

function TInfoPage.GetUpdateKeys: TStringArray;
begin
  Result := FUpdateKeys;
end;

procedure TInfoPage.LoadSettings;
begin

end;

procedure TInfoPage.SaveSettings;
begin

end;

procedure TInfoPage.SetGID(Value: TAria2GID);
begin
  FGID := Value;
end;

end.
