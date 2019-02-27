{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit ServiceMain;

interface

uses
  Windows, Messages, SysUtils, Classes, SvcMgr,
  NetTimeThread, ConfigObj, Mutex, NetTimeCommon, WinSvc, Logging;

type
  TNetTimeSvc = class(TService)
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
    procedure DoExitNow(Sender: TObject);
  private
    tt: TNetTimeServer;
    procedure WMEndSession(var Msg: TWMEndSession); message WM_ENDSESSION;
  public
    function GetServiceController: TServiceController; override;
  end;

var
  NetTimeSvc: TNetTimeSvc;

implementation

{$R *.DFM}

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  NetTimeSvc.Controller(CtrlCode);
end;

function TNetTimeSvc.GetServiceController: TServiceController;
begin
  Result:= ServiceController;
end;

procedure TNetTimeSvc.DoExitNow(Sender: TObject);
begin
  Controller(SERVICE_CONTROL_STOP);
end;

procedure TNetTimeSvc.ServiceStart(Sender: TService; var Started: Boolean);
var co: TConfigObj;
begin
  LogFileName:= ExtractFilePath(ParamStr(0)) + 'NetTimeLog.txt';

  if not GetExclusivity(ExNameServer) then
    raise exception.create('Cannot load NetTime server: Another server is already running');

  tt:= TNetTimeServer.create;
  co:= TConfigObj.create;
  try
    co.ReadFromRegistry;
    co.WriteToRunning(tt);
  finally
    co.Free;
  end;
  if (tt.Config.ServerCount = 0) then
    raise exception.create('NetTime has not been configured');
  tt.OnExitNow:= DoExitNow;
  tt.Start;
  Started:= true;
end;

procedure TNetTimeSvc.ServiceStop(Sender: TService; var Stopped: Boolean);
begin
  tt.Stop;
  Stopped:= true;
end;

procedure TNetTimeSvc.WMEndSession(var Msg: TWMEndSession);
begin
  DoExitNow(Self);
end;

end.
