{ ************************************************************************

   NetTime is copyrighted by Graham Mainwaring. Permission is hereby
   granted to use, modify, redistribute and create derivative works
   provided this attribution is not removed. I also request that if you
   make any useful changes, please e-mail the diffs to graham@mhn.org
   so that I can include them in an 'official' release.

   Modifications Copyright 2011 - Mark Griffiths

  ************************************************************************ }

program NetTimeService;

uses
  SysUtils, SvcMgr,
  ServiceMain in 'ServiceMain.pas' {NetTimeSvc: TService},
  NetTimeThread in 'NetTimeThread.pas',
  ConfigObj in 'ConfigObj.pas',
  mutex in 'mutex.pas',
  NetTimeCommon in 'NetTimeCommon.pas';

{$R *.RES}

begin
  Application.Initialize;
  Application.Title:= 'NetTime NT Service';
  ServiceMode:= True;
  Application.CreateForm(TNetTimeSvc, NetTimeSvc);
  try
    Application.Run;
  except on e: Exception do
    NetTimeSvc.LogMessage(e.Message);
  end;
end.
