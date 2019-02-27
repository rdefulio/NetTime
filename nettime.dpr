{ ************************************************************************

   NetTime is copyrighted by Graham Mainwaring. Permission is hereby
   granted to use, modify, redistribute and create derivative works
   provided this attribution is not removed. I also request that if you
   make any useful changes, please e-mail the diffs to graham@mhn.org
   so that I can include them in an 'official' release.

   Modifications Copyright 2011 - Mark Griffiths

  ************************************************************************ }

program NetTime;

uses
  Forms,
  Dialogs,
  SysUtils,
  tclfrm in 'tclfrm.pas' {frmMain},
  timeconv in 'timeconv.pas',
  TrayIcon in 'Trayicon.pas',
  Options in 'Options.pas' {frmOptions},
  About in 'About.pas' {frmAbout},
  warning in 'warning.pas' {frmWarning},
  ntptime in 'ntptime.pas',
  unixtime in 'unixtime.pas',
  timewrap in 'timewrap.pas',
  ConfigObj in 'ConfigObj.pas',
  NetTimeThread in 'NetTimeThread.pas',
  IsWinNT in 'IsWinNT.pas',
  mutex in 'mutex.pas',
  winerr in 'winerr.pas',
  NetTimeClient in 'NetTimeClient.pas',
  NetTimeCommon in 'NetTimeCommon.pas',
  WinsockUtil in 'WinsockUtil.pas',
  NetTimeIPC in 'NetTimeIPC.pas',
  serverlist in 'serverlist.pas',
  Logging in 'Logging.pas',
  WinUtils in 'WinUtils.pas',
  LogView in 'LogView.pas' {LogViewForm},
  UpdateCheck in 'UpdateCheck.pas';

{$R *.RES}

begin
  Application.Initialize;
  Application.ShowMainForm:= LowerCase(ParamStr(1)) = 'show';
  Application.Title:= 'Network Time Synchronizer';
//  Application.HelpFile:= 'NETTIME.HLP';
  Application.CreateForm(TfrmMain, frmMain);
  Application.CreateForm(TLogViewForm, LogViewForm);
  //  Application.CreateForm(TfrmAutoConfigure, frmAutoConfigure);
  //  if not ((ParamCount = 1) and (uppercase(ParamStr(1)) = '/NOSPLASH')) then
//    DoSplash;
  try
    frmMain.DoAppStartup;
  except on e: Exception do
    begin
      ShowMessage('Initialization failure:'#13#10#13#10+e.Message);
      halt;
    end;
  end;

  Application.Run;
end.
