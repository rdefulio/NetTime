{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit tclfrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, trayicon, Menus, Buttons, ExtCtrls, NetTimeCommon,
  About, Options, NetTimeThread, NetTimeClient, TimeConv, Logging, WinUtils,
  ConfigObj, cwinsvc, ShellAPI, ComCtrls, UpdateCheck, MyTime, WinsockUtil;

const
  PBT_APMPOWERSTATUSCHANGE = $0A;
  PBT_APMRESUMEAUTOMATIC = $12;
  PBT_APMRESUMESUSPEND = $07;
  PBT_APMSUSPEND = $04;
  PBT_POWERSTATECHANGE = $8013;

  // The following are not available on Windows Vista and above:
  PBT_APMBATTERYLOW = $09;
  PBT_APMOEMEVENT = $0B;
  PBT_APMQUERYSUSPEND = $00;
  PBT_APMQUERYSUSPENDFAILED = $02;
  PBT_APMRESUMECRITICAL = $06;

type
  TNetTimeMode = (ntm_NotSet, ntm_Standalone, ntm_Service, ntm_WaitingForService);

type
  TfrmMain = class(TForm)
    lblTime: TLabel;
    lblGoodness: TLabel;
    lblLastSync: TLabel;
    Label1: TLabel;
    Label2: TLabel;
    mnuTray: TPopupMenu;
    Properties1: TMenuItem;
    N1: TMenuItem;
    Exit1: TMenuItem;
    imgBad: TImage;
    imgGood: TImage;
    btnSettings: TButton;
    Timer1: TTimer;
    About: TButton;
    lblSource: TLabel;
    btnUpdateNow: TButton;
    UpdateNow1: TMenuItem;
    imgWarn: TImage;
    Label8: TLabel;
    btnStartStop: TButton;
    lblLastSyncAttempt: TLabel;
    Label4: TLabel;
    lblNextSync: TLabel;
    Label5: TLabel;
    About1: TMenuItem;
    Label3: TLabel;
    lblLastErrorReason: TLabel;
    ServerInfo: TListView;
    Close: TButton;
    UpdateCheckTimer: TTimer;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Exit1Click(Sender: TObject);
    procedure Properties1Click(Sender: TObject);
    procedure BitBtn1Click(Sender: TObject);
    procedure About1Click(Sender: TObject);
    procedure btnSettingsClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnUpdateNowClick(Sender: TObject);
    procedure UpdateNow1Click(Sender: TObject);
    procedure btnStartStopClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure UpdateCheckTimerTimer(Sender: TObject);
  private
    ShowConfig: boolean;
    StopOnTimer: boolean;
    ManualShutdown: boolean;
    Mode: TNetTimeMode;
    TaskbarCreatedMsg: Cardinal;

    procedure WMEndSession(var Msg: TWmEndSession); message WM_ENDSESSION;
    procedure ClockSyncLost;
    procedure SetServiceMode;
    procedure SetWaitingForServiceMode;
    Procedure ShutDownService;
    Procedure StartService;
    Procedure SetUpdateCheckTimer;
    procedure FinishSetup;
    function UpdateNow: boolean;
    function RunAsAdmin(Command: string; Wait: boolean): boolean;
  public
    tt: TNetTimeServerBase;
    ti: TrayIcon.TTrayIcon;  // Fix for newer versions of Delphi
    procedure DoAppStartup;
    Procedure StartStandaloneMode;
    procedure TimeStateChange(Sender: TObject);
    function WarnAdjust(const Sender: TObject; const ServerTime, StationTime: TDateTime): boolean;
    procedure DoExitNow(Sender: TObject);

    procedure WndProc(var message: TMessage); override;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.DFM}
{$R Windows7.RES}

uses Warning, timewrap, iswinnt, mutex;

procedure TfrmMain.SetServiceMode;
begin
  Mode:= ntm_Service;
  lblSource.Caption:= 'Mode: Windows Service';
  btnStartStop.Caption:= '&Stop';
  btnStartStop.Left:= lblSource.Left + lblSource.Width + 10;
  btnStartStop.Visible:= true;
  tt:= TNetTimeProxy.Create;
end;

procedure TfrmMain.SetWaitingForServiceMode;
begin
  FreeAndNil(tt);
  Mode:= ntm_WaitingForService;
  lblNextSync.Caption:= '';
  lblSource.Caption:= 'Mode: Windows Service (Not Running)';
  btnStartStop.Caption:= '&Start';
  btnStartStop.Left:= lblSource.Left + lblSource.Width + 10;
  btnStartStop.Visible:= true;
  btnStartStop.Refresh;  // Fixes a strange drawing problem with the button!

  ServerInfo.Items.Clear;
end;

Procedure TfrmMain.SetUpdateCheckTimer;
begin
  UpdateCheckTimer.Enabled:= AutomaticUpdateChecksEnabled;
end;

procedure TfrmMain.FinishSetup;
begin
  if Assigned(tt) then
    begin
      tt.OnWarnAdj:= WarnAdjust;
      tt.OnStateChange:= TimeStateChange;
      tt.OnExitNow:= DoExitNow;
      tt.ForceUpdate;
      TimeStateChange(Self);
    end;

  lblSource.Visible:= true;
  Timer1.Enabled:= true;
  ti.Active:= true;
  TaskbarCreatedMsg:= RegisterWindowMessage('TaskbarCreated');

  SetUpdateCheckTimer;
end;

Procedure TfrmMain.StartStandaloneMode;
var co: TConfigObj;
begin
  if Mode = ntm_Standalone then
    exit;

  if not HaveAdminPrivileges then
    begin
      if UACEnabled then
        begin
          if MessageDlg('NetTime requires administrative privileges when running in standalone mode!'#13#10#13#10 +
                        'Please configure NetTime as a service if you want limited users to be able to use it!'#13#10#13#10 +
                        'Would you like to configure NetTime to run as a service now?', mtInformation, [mbYes, mbNo], 0) = mrYes then
            begin
              if RunAsAdmin('/installservice', True) then
                begin
                  SetWaitingForServiceMode;
                  FinishSetup;
                  exit;
                end;
            end;
        end;
    raise Exception.Create('NetTime requires administrative privileges when running in standalone mode!'#13#10#13#10 +
                           'Please configure NetTime as a service if you want limited users to be able to use it!');
    end;

  if not GetExclusivity(ExNameStandalone) then
    raise Exception.Create('NetTime is already running in standalone mode in another session.'#13#10#13#10 +
      'Please configure NetTime as a service if you want to use NetTime with fast user switching!');

  Mode:= ntm_Standalone;
  lblSource.Caption:= 'Mode: Standalone Application';
  btnStartStop.Visible:= False;
  tt:= TNetTimeServer.Create;

  co:= TConfigObj.Create;
  co.ReadFromRegistry;

  co.WriteToRunning(tt);
  co.Free;

  (tt as TNetTimeServer).Start(False);

  FinishSetup;
end;

procedure TfrmMain.DoAppStartup;
var co: TConfigObj;
    Command: string;
begin
  co:= TConfigObj.Create;
  co.ReadFromRegistry;

  try
    Command:= LowerCase(ParamStr(1));

    if Command = '/showconfig' then
      ShowConfig:= true;

    if Command = '/installservice' then
      begin
  //      UninstallNetTimeService;  // Disabled 5/5/2012 by MTG - can cause an error about the service being marked for deletion!
        InstallNetTimeService(true);
        ServiceStart('', ExNameService);
        Application.Terminate;
        exit;
      end;

    if Command = '/enableautostart' then
      begin
        SetAutoStart(true);

        Application.Terminate;
        exit;
      end;

    if Command = '/uninstall' then
      begin
        GetExclusivity(ExNameUIShutdown);

        ServiceStop('', ExNameService);
        UninstallNetTimeService;
        SetAutoStart(False);

        Sleep(1000);

        Application.Terminate;
        exit;
      end;

    if Command = '/startservice' then
      begin
        if not ServiceStart('', ExNameService) then
          ShowMessage('Unable to start Service!');

        Application.Terminate;
        exit;
      end;

    if Command = '/stopservice' then
      begin
        if not ServiceStop('', ExNameService) then
          ShowMessage('Unable to stop Service!');

        Application.Terminate;
        exit;
      end;

    if not GetExclusivity(ExNameUI) then
      begin
        Application.Terminate;
        exit;
      end;

    ti:= TrayIcon.TTrayIcon.Create(Application);  // Fix for newer versions of Delphi
    ti.ToolTip:= 'Network Time Synchronization';
    ti.PopupMenu:= mnuTray;
    ti.Icon:= imgBad.Picture.Icon;
    ti.OnClick:= Properties1Click;
    ti.OnDblClick:= Properties1Click;

    if Command = '/firstrun' then
      begin
        ti.Active:= True;
        ti.ShowBalloonTip('Click this tray icon to show NetTime.', 'NetTime is Running!');
      end;

    if not CheckExclusivity(ExNameServer) then
      begin
        SetServiceMode;
        FinishSetup;
        exit;
      end;

    if co.ServiceOnBoot then
      begin
        SetWaitingForServiceMode;
        FinishSetup;
        exit;
      end;

  finally
    co.Free;
  end;

  StartStandaloneMode;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if LowerCase(ParamStr(1)) <> 'show' then
    begin
      Action:= caNone;
      Self.Hide;
    end;
end;

procedure TfrmMain.Exit1Click(Sender: TObject);
begin
  if MessageDlg('Are you sure that you want to completely shut down NetTime?'+crlf+crlf+
                'Your system time will no longer be kept in sync!',
                      mtInformation, [mbYes, mbNo], 0) = mrNo then
    exit;

  ManualShutdown:= True;
  LogMessage('Manual Shutdown', log_Debug);
  ShutdownService;
  Application.Terminate;
end;

procedure TfrmMain.Properties1Click(Sender: TObject);
begin
  Self.Show;
  Application.Restore;
  SetForegroundWindow(Application.Handle);
end;

procedure TfrmMain.BitBtn1Click(Sender: TObject);
begin
  Self.Hide;
end;

procedure TfrmMain.About1Click(Sender: TObject);
begin
  ShowAboutForm;
end;

procedure TfrmMain.btnSettingsClick(Sender: TObject);
var
  fO: TfrmOptions;
begin
  if not HaveAdminPrivileges then
    begin
      if UACEnabled then
        begin
          ReleaseExclusivity(ExNameUI);

          if RunAsAdmin('/showconfig', False) then
            Application.Terminate
          else
            GetExclusivity(ExNameUI);
        end
      else
        ShowMessage('Administrative privileges required to change settings!');

      exit;
    end;

  UpdateCheckTimer.Enabled:= False;

  fO:= TfrmOptions.Create(Application);
  fO.tt:= tt;
  fO.ShowModal;
  fO.Release;

  if IsWindowsNT then
    begin
      if fO.co.ServiceOnBoot then
        ServiceStart('', ExNameService)
      else
        begin
          ServiceStop('', ExNameService);

          StartStandaloneMode;
        end;
    end;

  GetNextUpdateCheckDue;
  SetUpdateCheckTimer;
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  TimeStateChange(Sender);
end;

procedure TfrmMain.ClockSyncLost;
begin
  lblGoodness.Caption:= 'CLOCK SYNC LOST!';
  ti.ToolTip:= 'Network Time Synchronization' + #13#10 + lblGoodness.Caption;
  ti.Icon:= imgBad.Picture.Icon;
end;

procedure TfrmMain.TimeStateChange(Sender: TObject);
var
  tip: string;
  i: Integer;
  AllGood: boolean;
  ServerData: TServerData;
  Status: TSyncServerStatus;
  ListItem: TListItem;
  ServerNameStr: String;
  StatusStr: String;
  OffsetStr: String;
  LagStr: String;
  LastErrorStr: String;
begin
  if not Assigned(tt) then
    exit;

  try
    tip:= 'Network Time Synchronization';

    if tt.LastUpdateAttemptTime = 0 then
      lblLastSyncAttempt.Caption:= 'No attempt yet'
    else
      lblLastSyncAttempt.Caption:= DateTimeToStr(tt.LastUpdateAttemptTime);

    if tt.LastSuccessfulUpdateTime = 0 then
      lblLastSync.Caption:= 'No synchronization yet'
    else
      begin
        lblLastSync.Caption:= DateTimeToStr(tt.LastSuccessfulUpdateTime) + ' ' + GetOffsetStr(tt.Status.OffSet);
        tip:= tip + #13#10 + 'Last Sync: ' + DateTimeToStr(tt.LastSuccessfulUpdateTime);
      end;

    if (tt.Status.Synchronized) then
      begin
        lblGoodness.Caption:= 'Time is synchronized.';
        AllGood:= true;
        for i:= 0 to MaxServers - 1 do
          if not(tt.Status.ServerDataArray[i].Status in [ssGood, ssUnconfigured, ssNotUsed]) then
            AllGood:= False;
        if AllGood then
          ti.Icon:= imgGood.Picture.Icon
        else
          ti.Icon:= imgWarn.Picture.Icon;
      end
    else
      ClockSyncLost;

    ServerInfo.Items.Clear;

    for i:= 0 to tt.Config.ServerCount - 1 do
      begin
        ListItem:= ServerInfo.Items.Add;

        ServerNameStr:= '';
        StatusStr:= '';
        OffsetStr:= '';
        LagStr:= '';
        LastErrorStr:= '';

        ServerData:= tt.Status.ServerDataArray[i];
        Status:= ServerData.Status;

        if (Status = ssNotUsed) and (ServerData.ErrorTimeOut > 0) then
          begin
            Status:= ServerData.ErrorStatus;
            LastErrorStr:= DateTimeToStr(ServerData.LastErrorTime);
          end;

        if Status in [ssNotUsed .. ssKoD] then
          begin
            ServerNameStr:= tt.Config.Servers[i].Hostname;
            StatusStr:= SyncServerStatusToStr(Status);

            if ServerData.Status in [ssGood, ssWrong] then
              begin
                OffsetStr:= GetOffsetStr(ServerData.OffSet);
                LagStr:= IntToStr(ServerData.TimeLag) + 'ms';
              end;
          end;

        ListItem.Caption:= ServerNameStr;
        ListItem.SubItems.Add(StatusStr);
        ListItem.SubItems.Add(OffsetStr);
        ListItem.SubItems.Add(LagStr);
        ListItem.SubItems.Add(LastErrorStr);
      end;

    if tt.Status.LastSyncError <> lse_None then
      lblLastErrorReason.Caption:= DateTimeToStr(tt.Status.LastErrorTime) + ' (' +
        LastSyncErrorToStr(tt.Status.LastSyncError) + ')';

    ti.ToolTip:= tip;
    if IsWindowsNT then
      SetProcessWorkingSetSize(GetCurrentProcess, $FFFFFFFF, $FFFFFFFF);
  except
  end;
end;

function TfrmMain.WarnAdjust(const Sender: TObject; const ServerTime, StationTime: TDateTime): boolean;
var
  fW: TfrmWarning;
begin
  fW:= TfrmWarning.Create(Application);
  fW.lblServerTime.Caption:= DateTimeToStr(ServerTime);
  fW.lblStationTime.Caption:= DateTimeToStr(StationTime);
  fW.ShowModal;
  result:= not fW.rbnShutdown.Checked;
  fW.Free;
end;

procedure TfrmMain.DoExitNow(Sender: TObject);
begin
  StopOnTimer:= true;
  Timer1.Interval:= 50;
  Timer1.Enabled:= True;
end;

procedure TfrmMain.Timer1Timer(Sender: TObject);
begin
  if not CheckExclusivity(ExNameUIShutdown) then
    StopOnTimer:= true;

  if StopOnTimer then
    begin
      Timer1.Enabled:= False;
      if tt is TNetTimeServer then
        (tt as TNetTimeServer).Stop;
      tt.Free;
      ti.Free;
      Application.Terminate;
      exit;
    end;

  if ShowConfig then
    begin
      ShowConfig:= False;
      Show;
      btnSettingsClick(Self);
      exit;
    end;

  if Mode = ntm_Standalone then
    begin
      if Assigned(tt) then
        begin
          Assert(tt is TNetTimeServer);
          if not (tt as TNetTimeServer).Active then
            begin
              Application.Terminate;
              exit;
            end;
        end;
    end;

  if Mode <> ntm_Service then
    begin
      // Check to see if the service has suddenly started!

      if not CheckExclusivity(ExNameServer) then
        begin
          Timer1.Enabled:= False;

          if Mode = ntm_Standalone then
            ReleaseExclusivity(ExNameStandalone);

          if Assigned(tt) then
            begin
              Assert(tt is TNetTimeServer);
              (tt as TNetTimeServer).Stop;
              FreeAndNil(tt);
            end;

          // Allow a second for the server to finish setting up - just in case!
          Sleep(1000);

          SetServiceMode;
          FinishSetup;
          Timer1.Enabled:= True;
        end;
    end;

  if not Visible then
    exit;

  lblTime.Caption:= DateTimeToStr(Now);

  if Assigned(tt) then
    begin
      try
        tt.ForceUpdate;
      except
        Timer1.Enabled:= False;
        SetWaitingForServiceMode;
        ClockSyncLost;
        Timer1.Enabled:= True;
        exit;
      end;
      if tt.DoingSync then
        lblNextSync.Caption:= 'Doing Sync Now!'
      else
        lblNextSync.Caption:= SecondsToStr(tt.TimeToNextUpdate);
    end;
end;

procedure TfrmMain.AboutClick(Sender: TObject);
begin
  ShowAboutForm;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  LogFileName:= ExtractFilePath(ParamStr(0)) + 'NetTimeLog.txt';

  StopOnTimer:= False;
end;

function TfrmMain.UpdateNow: boolean;
begin
  result:= False;

  Screen.Cursor:= crHourglass;
  try
    if not Assigned(tt) then
      begin
        ShowMessage('NetTime service isn''t running!');
        exit;
      end;

    result:= tt.UpdateNow;

    TimeStateChange(Self);

    if not result then
      ShowMessage('Error: Could not update.');
  finally
    Screen.Cursor:= crDefault;
  end;
end;

function TfrmMain.RunAsAdmin(Command: string; Wait: boolean): boolean;
var
  ShellExecuteInfo: TShellExecuteInfo;
  IExit: Cardinal;
begin
  result:= False;

  if (not HaveAdminPrivileges) and UACEnabled then
    begin
      FillChar(ShellExecuteInfo, SizeOf(ShellExecuteInfo), 0);
      ShellExecuteInfo.cbSize:= SizeOf(ShellExecuteInfo);
      ShellExecuteInfo.lpVerb:= 'runas';
      ShellExecuteInfo.lpFile:= PChar(ParamStr(0));
      ShellExecuteInfo.lpParameters:= PChar(Command);
      ShellExecuteInfo.lpDirectory:= PChar(ExtractFilePath(ParamStr(0)));
      ShellExecuteInfo.nShow:= SW_NORMAL;
      ShellExecuteInfo.fMask:= SEE_MASK_NOCLOSEPROCESS;

      // if ShellExecute(0, 'runas', PChar(ParamStr(0)), PChar(Command), PChar(ExtractFilePath(ParamStr(0))), SW_NORMAL) > 32 then
      if ShellExecuteEx(@ShellExecuteInfo) then
        begin
          if Wait then
            repeat
              GetExitCodeProcess(ShellExecuteInfo.hProcess, IExit);
              { Allow the application to do things while we are idle waiting. }
              if IExit = STILL_ACTIVE then
                begin
                  { Allow the application to do redraws etc. }
                  Application.ProcessMessages;
                  { Give up this timeslice to other processes. }
                  Sleep(55);
                end;
            until IExit <> STILL_ACTIVE;

          result:= true;

          CloseHandle(ShellExecuteInfo.hProcess);
        end;
    end;
end;

procedure TfrmMain.btnUpdateNowClick(Sender: TObject);
begin
  UpdateNow;
end;

procedure TfrmMain.UpdateNow1Click(Sender: TObject);
begin
  if UpdateNow then
    ShowMessage('Update successful. The time is now ' + DateTimeToStr(Now));
end;

procedure TfrmMain.WMEndSession(var Msg: TWmEndSession);
begin
  Application.Terminate;
end;

Procedure TfrmMain.ShutDownService;
var ServiceStopped: boolean;
begin
  if Mode <> ntm_Service then
    exit;

  Timer1.Enabled:= False;
  try
    Screen.Cursor:= crHourglass;

    if HaveAdminPrivileges then
      ServiceStopped:= ServiceStop('', ExNameService)
    else
      begin
        if UACEnabled then
          begin
            RunAsAdmin('/stopservice', true);
            Sleep(1000);
            ServiceStopped:= cwinsvc.ServiceStopped('', ExNameService);
          end
        else
          begin
            ShowMessage('Administrator privileges required to stop the service!');
            exit;
          end;
      end;

    if ServiceStopped then
      begin
        SetWaitingForServiceMode;
        ClockSyncLost;
      end
    else
      begin
        ShowMessage('Unable to stop Service!');
      end;
  finally
    Screen.Cursor:= crDefault;
    Timer1.Enabled:= True;
  end;
end;

Procedure TfrmMain.StartService;
var ServiceStarted: Boolean;
begin
  try
    Screen.Cursor:= crHourglass;

    if HaveAdminPrivileges then
      ServiceStarted:= ServiceStart('', ExNameService)
    else
      begin
        if UACEnabled then
          begin
            RunAsAdmin('/startservice', true);
            ServiceStarted:= ServiceRunning('', ExNameService);
          end
        else
          begin
            ShowMessage('Administrator privileges required to start the service!');
            exit;
          end;
      end;

    if not ServiceStarted then
      ShowMessage('Unable to start Service!');
  finally
    Screen.Cursor:= crDefault;
  end;
end;

procedure TfrmMain.btnStartStopClick(Sender: TObject);
begin
  case Mode of
    ntm_Service:
      begin
        if MessageDlg('This shuts down the currently running service. Are you sure that you want to do this?',
                      mtInformation, [mbYes, mbNo], 0) = mrYes then
          ShutDownService;
      end;
    ntm_WaitingForService:
      StartService;
  end;
end;

procedure TfrmMain.WndProc(var message: TMessage);
begin
  if message.Msg = WM_POWERBROADCAST then
    begin
      case message.wParam of
        // PBT_APMQUERYSUSPEND: LogMessage('Windows Message: Query Suspend', log_Debug);
        PBT_APMPOWERSTATUSCHANGE:
          LogMessage('Windows Message: Power Status Change', log_Debug);
        PBT_APMRESUMESUSPEND:
          LogMessage('Windows Message: Manually Resumed', log_Debug);
        PBT_POWERSTATECHANGE:
          LogMessage('Windows Message: Power State Change', log_Debug);
        PBT_APMSUSPEND:
          begin
            LogMessage('Windows Message: Suspending', log_Debug);
            tt.WindowsSuspending;
          end;
        PBT_APMRESUMEAUTOMATIC:
          begin
            LogMessage('Windows Message: Resumed', log_Debug);
            tt.WindowsResuming;
          end;

        // The following are not available on Windows Vista and above!
        PBT_APMBATTERYLOW:
          LogMessage('Windows Message: Battery Low', log_Debug);
        PBT_APMOEMEVENT:
          LogMessage('Windows Message: OEM Power Event', log_Debug);
        PBT_APMQUERYSUSPEND:
          LogMessage('Windows Message: Query Suspend', log_Debug);
        PBT_APMQUERYSUSPENDFAILED:
          LogMessage('Windows Message: Query Suspend Failed', log_Debug);
        PBT_APMRESUMECRITICAL:
          LogMessage('Windows Message: Resume from Critical Suspension', log_Debug);
      else
        LogMessage('Windows Message - Unknown Power Broadcast Code: ' + IntToStr(message.wParam), log_Debug);
      end;
    end;

  if Message.Msg = TaskbarCreatedMsg then
    begin
      // Windows Explorer has crashed!  Show the tray icon again!
      ti.Active:= False;
      ti.Active:= True;
    end;

  inherited WndProc(message);
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  if not ManualShutdown then
    LogMessage('NetTime Closing', log_Debug);
end;

procedure TfrmMain.CloseClick(Sender: TObject);
begin
  if LowerCase(ParamStr(1)) = 'show' then
    Application.Terminate
  else
    Hide;
end;

procedure TfrmMain.UpdateCheckTimerTimer(Sender: TObject);
const NetworkActiveCount: Integer = 0;
begin
  if SystemTimeAsUnixTime < GetNextUpdateCheckDue then
    exit;

  if not HaveLocalAddress then
    begin
      NetworkActiveCount:= 0;
      exit;
    end;

  Inc(NetworkActiveCount);

  if NetworkActiveCount >= NetworkWakeupSeconds + 1 then
    begin
      UpdateCheckTimer.Enabled:= False;

      CheckForUpdates(False);

      UpdateCheckTimer.Enabled:= True;
      
      NetworkActiveCount:= 0;
    end;
end;

end.
