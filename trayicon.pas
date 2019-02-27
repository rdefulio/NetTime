{ TTrayIcon VCL. Version 1.3

  Requires:  Delphi 2.0 32 bit.

  Function: Adds an icon to the Windows 95 Tool Tray and
  has events to respond to mouse clicks.

  This component is based on the TToolIcon VCL that was written by
  Derek Stutsman (dereks@metronet.com).  He based his component on
  TWinControl, so it showed up as a clear, blank, resizable window at
  design time and also had more properties than the component actually
  needed.  This made it really hard to find on a busy form sometimes.

  I changed it so it would be based on TComponent so that it was readily
  visible at design time and also did not cover anything at run-time.
  The additional Top, left, width, etc. properties are also no longer
  necessary.  I added a ShowDesigning property so that you could test
  it at design time, but then turn it off so that TWO icons weren't shown
  on the tool tray when developing and testing.

  One strange anomaly that I worked around but don't know why it happens -
  if a ToolTip is not specified, then at run-time the icon shows up as
  blank.  If a ToolTip is specified, everything works fine.  To fix this,
  I set up another windows message that set the tool tip if it was blank -
  this ensures proper operation at all times, but I don't know why this
  is necessary.  If you can figure it out, send me some mail and let me
  know! (4/17/96 note - still no solution for this!)

  This is freeware (as was the original).  If you make cool changes to it,
  please send them to me.

  Enjoy!

  Pete Ness
  Compuserve ID: 102347,710
  Internet: 102347.710@compuserve.com
  http:\\ourworld.compuserve.com\homepages\peteness

  Release history:

  3/8/96 - Version 1.0
  Release by Derek Stutsman of TToolIcon version 1.0

  3/12/96 - Version 1.1

  Changed as outlined above by me (Pete Ness) and renamed to TTrayIcon.

  3/29/96 - Version 1.2
  Add default window handling to allow closing when Win95 shutdown.
  Previously, you had to manually close your application before closing
  Windows 95.

  4/17/96 - Version 1.3
  Added a PopupMenu property to automatically handle right clicking on
  the tray icon.
  Fixed bug that would not allow you to instantiate a TTrayIcon instance
  at run-time.
  Added an example program to show how to do some of the things I've
  gotten the most questions on.
  This version is available from my super lame web page - see above for
  the address.

  25/2/2012 Mark Griffiths: Added code to show Balloon Tips based on code by happyjoe@21cn.com
}

unit TrayIcon;

interface

uses
  SysUtils, Windows, Messages, Classes, Graphics, Controls, ShellAPI, Forms, menus;

const
  WM_TOOLTRAYICON = WM_USER + 1;
  WM_RESETTOOLTIP = WM_USER + 2;

  NIF_INFO = $10;
  NIF_MESSAGE = 1;
  NIF_ICON = 2;
  NOTIFYICON_VERSION = 3;
  NIF_TIP = 4;
  NIM_SETVERSION = $00000004;
  NIM_SETFOCUS = $00000003;
  NIIF_INFO = $00000001;
  NIIF_WARNING = $00000002;
  NIIF_ERROR = $00000003;

  NIN_BALLOONSHOW = WM_USER + 2;
  NIN_BALLOONHIDE = WM_USER + 3;
  NIN_BALLOONTIMEOUT = WM_USER + 4;
  NIN_BALLOONUSERCLICK = WM_USER + 5;
  NIN_SELECT = WM_USER + 0;
  NINF_KEY = $1;
  NIN_KEYSELECT = NIN_SELECT or NINF_KEY;

  {define the callback message}
  TRAY_CALLBACK = WM_USER + $7258;

type

  PNewNotifyIconData = ^TNewNotifyIconData;
  TDUMMYUNIONNAME    = record
    case Integer of
      0: (uTimeout: UINT);
      1: (uVersion: UINT);
  end;

  TNewNotifyIconData = record
    cbSize: DWORD;
    Wnd: HWND;
    uID: UINT;
    uFlags: UINT;
    uCallbackMessage: UINT;
    hIcon: HICON;
   //Version 5.0 is 128 chars, old ver is 64 chars
    szTip: array [0..127] of Char;
    dwState: DWORD; //Version 5.0
    dwStateMask: DWORD; //Version 5.0
    szInfo: array [0..255] of Char; //Version 5.0
    DUMMYUNIONNAME: TDUMMYUNIONNAME;
    szInfoTitle: array [0..63] of Char; //Version 5.0
    dwInfoFlags: DWORD;   //Version 5.0
  end;

  TTrayIcon = class(TComponent)

  private

    { Field Variables }

    IconData: TNewNotifyIconData;
    fIcon: TIcon;
    fToolTip: string;
    fWindowHandle: HWND;
    fActive: boolean;
    fShowDesigning: boolean;

    { Events }

    fOnClick: TNotifyEvent;
    fOnDblClick: TNotifyEvent;
    fOnRightClick: TMouseEvent;
    fPopupMenu: TPopupMenu;

    function AddIcon: boolean;
    function ModifyIcon: boolean;
    function DeleteIcon: boolean;

    procedure SetActive(Value: boolean);
    procedure SetShowDesigning(Value: boolean);
    procedure SetIcon(Value: TIcon);
    procedure SetToolTip(Value: string);
    procedure WndProc(var msg: TMessage);

    procedure FillDataStructure;
    procedure DoRightClick(Sender: TObject);
  protected

  public

    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
    procedure ShowBalloonTip(Msg, Title: String; TimeOut: Integer = 5000; InfoFlags: DWord = 0);

  published

    property Active: boolean read fActive write SetActive;
    property ShowDesigning: boolean read fShowDesigning write SetShowDesigning;
    property Icon: TIcon read fIcon write SetIcon;
    property ToolTip: string read fToolTip write SetToolTip;

    property OnClick: TNotifyEvent read fOnClick write fOnClick;
    property OnDblClick: TNotifyEvent read fOnDblClick write fOnDblClick;
    property OnRightClick: TMouseEvent read fOnRightClick write fOnRightClick;
    property PopupMenu: TPopupMenu read fPopupMenu write fPopupMenu;

  end;

procedure register;

implementation

{$R TrayIcon.res}

// The following commented out code may be useful as a basis if we want to add in
// the capability to respond to the balloon tip being clicked or to know when it has timed out, etc!

(*);
procedure TForm1.SysTrayIconMsgHandler(var Msg: TMessage);
begin
  case Msg.lParam of
    WM_MOUSEMOVE:;
    WM_LBUTTONDOWN:;
    WM_LBUTTONUP:;
    WM_LBUTTONDBLCLK:;
    WM_RBUTTONDOWN:;
    WM_RBUTTONUP:;
    WM_RBUTTONDBLCLK:;
    //followed by the new messages
    NIN_BALLOONSHOW:
    {Sent when the balloon is shown}
      ShowMessage('NIN_BALLOONSHOW');
    NIN_BALLOONHIDE:
    {Sent when the balloon disappears?Rwhen the icon is deleted,
    for example. This message is not sent if the balloon is dismissed because of
    a timeout or mouse click by the user. }
      ShowMessage('NIN_BALLOONHIDE');
    NIN_BALLOONTIMEOUT:
    {Sent when the balloon is dismissed because of a timeout.}
      ShowMessage('NIN_BALLOONTIMEOUT');
    NIN_BALLOONUSERCLICK:
    {Sent when the balloon is dismissed because the user clicked the mouse.
    Note: in XP there's Close button on he balloon tips, when click the button,
    send NIN_BALLOONTIMEOUT message actually.}
      ShowMessage('NIN_BALLOONUSERCLICK');
  end;
end;

  {AddSysTrayIcon procedure add an icon to notification area}
procedure TForm1.AddSysTrayIcon;
begin
  IconData.cbSize := SizeOf(IconData);
  IconData.Wnd := AllocateHWnd(SysTrayIconMsgHandler);
  {SysTrayIconMsgHandler is then callback message' handler}
  IconData.uID := 0;
  IconData.uFlags := NIF_ICON or NIF_MESSAGE or NIF_TIP;
  IconData.uCallbackMessage := TRAY_CALLBACK;   //user defined callback message
  IconData.hIcon := Application.Icon.Handle;    //an Icon's Handle
  IconData.szTip := 'Please send me email.';
  if not Shell_NotifyIcon(NIM_ADD, @IconData) then
    ShowMessage('add fail');
end;
*)

procedure TTrayIcon.SetActive(Value: boolean);
begin
  if Value <> fActive then
    begin
      fActive:= Value;
      if not(csdesigning in ComponentState) then
        begin
          if Value then
            begin
              AddIcon;
            end
          else
            begin
              DeleteIcon;
            end;
        end;
    end;
end;

procedure TTrayIcon.SetShowDesigning(Value: boolean);
begin
  if csdesigning in ComponentState then
    begin
      if Value <> fShowDesigning then
        begin
          fShowDesigning:= Value;
          if Value then
            begin
              AddIcon;
            end
          else
            begin
              DeleteIcon;
            end;
        end;
    end;
end;

procedure TTrayIcon.SetIcon(Value: TIcon);
begin
  if Value <> fIcon then
    begin
      fIcon.Assign(Value);
      ModifyIcon;
    end;
end;

procedure TTrayIcon.SetToolTip(Value: string);
begin

  // This routine ALWAYS re-sets the field value and re-loads the
  // icon.  This is so the ToolTip can be set blank when the component
  // is first loaded.  If this is changed, the icon will be blank on
  // the tray when no ToolTip is specified.

  if length(Value) > 62 then
    Value:= copy(Value, 1, 62);
  fToolTip:= Value;
  ModifyIcon;
end;

constructor TTrayIcon.Create(aOwner: TComponent);
begin
  inherited create(aOwner);
  fWindowHandle:= {$WARNINGS OFF} AllocateHWnd(WndProc); {$WARNINGS ON}
  fIcon:= TIcon.create;
end;

destructor TTrayIcon.Destroy;
begin

  if (not(csdesigning in ComponentState) and fActive) or ((csdesigning in ComponentState) and fShowDesigning) then
    DeleteIcon;

  fIcon.Free;
{$WARNINGS OFF} DeAllocateHWnd(fWindowHandle); {$WARNINGS ON}
  inherited destroy;

end;

procedure TTrayIcon.FillDataStructure;
begin
  IconData.cbSize:= SizeOf(IconData);  // Fix for newer versions of Delphi
  with IconData do
    begin
      wnd:= fWindowHandle;
      uID:= 0; // is not passed in with message so make it 0
      uFlags:= NIF_MESSAGE + NIF_ICON + NIF_TIP;
      hIcon:= fIcon.Handle;
      StrPCopy(szTip, fToolTip);
      uCallbackMessage:= WM_TOOLTRAYICON;
    end;
end;

function TTrayIcon.AddIcon: boolean;
begin
  FillDataStructure;
  result:= Shell_NotifyIcon(NIM_ADD, @IconData);

  // For some reason, if there is no tool tip set up, then the icon
  // doesn't display.  This fixes that.

  if fToolTip = '' then
    PostMessage(fWindowHandle, WM_RESETTOOLTIP, 0, 0);

end;

function TTrayIcon.ModifyIcon: boolean;
begin
  FillDataStructure;
  if fActive then
    result:= Shell_NotifyIcon(NIM_MODIFY, @IconData)
  else
    result:= True;
end;

procedure TTrayIcon.DoRightClick(Sender: TObject);
var
  MouseCo: Tpoint;
begin

  GetCursorPos(MouseCo);

  if assigned(fPopupMenu) then
    begin
      SetForegroundWindow(Application.Handle);
      Application.ProcessMessages;
      fPopupMenu.Popup(MouseCo.X, MouseCo.Y);
    end;

  if assigned(fOnRightClick) then
    begin
      fOnRightClick(self, mbRight, [], MouseCo.X, MouseCo.Y);
    end;
end;

function TTrayIcon.DeleteIcon: boolean;
begin
  result:= Shell_NotifyIcon(NIM_DELETE, @IconData);
end;

procedure TTrayIcon.WndProc(var msg: TMessage);
begin
  with msg do
    if (msg = WM_RESETTOOLTIP) then
      SetToolTip(fToolTip)
    else
      if (msg = WM_TOOLTRAYICON) then
        begin
          case lParam of
            WM_LBUTTONDBLCLK:
              if assigned(fOnDblClick) then
                fOnDblClick(self);
            WM_LBUTTONUP:
              if assigned(fOnClick) then
                fOnClick(self);
            WM_RBUTTONUP:
              DoRightClick(self);
          end;
        end
      else // Handle all messages with the default handler
        result:= DefWindowProc(fWindowHandle, msg, wParam, lParam);

end;

Procedure TTrayIcon.ShowBalloonTip(Msg, Title: String; TimeOut: Integer = 5000; InfoFlags: DWord = 0);
begin
  IconData.cbSize:= SizeOf(IconData);
  IconData.uFlags:= NIF_INFO;
  strPLCopy(IconData.szInfo, Msg, SizeOf(IconData.szInfo) - 1);
  IconData.DUMMYUNIONNAME.uTimeout:= TimeOut;
  strPLCopy(IconData.szInfoTitle, Title, SizeOf(IconData.szInfoTitle) - 1);
  IconData.dwInfoFlags:= InfoFlags; // NIIF_INFO;     //NIIF_ERROR;  //NIIF_WARNING;
  Shell_NotifyIcon(NIM_MODIFY, @IconData);
  IconData.DUMMYUNIONNAME.uVersion:= NOTIFYICON_VERSION;
  Shell_NotifyIcon(NIM_SETVERSION, @IconData);
end;

procedure register;
begin
  RegisterComponents('Win95', [TTrayIcon]);
end;

end.
