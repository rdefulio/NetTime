{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit NetTimeThread;

interface

uses
  Windows, Forms, SysUtils, Classes, timewrap, unixtime, ntptime, ComObj,
  NetTimeCommon, NetTimeIPC, Winsock, Logging, MyStr, FileVersion, ConfigObj;

type

  TTimeThread = class;
  TTimeWatcher = class;

  TNetTimeServer = class(TNetTimeServerBase)
  private
    ttime: TTimeThread;
    ttwatch: TTimeWatcher;

    FActive: boolean;
    FServerCount: integer;
    FServers: TServerDefArray;
    FSyncFreq: integer;
    FSyncFreqUnits: Integer;
    FLostSync: integer;
    FLostSyncUnits: Integer;
    FRetry: integer;
    FRetryUnits: Integer;
    FLargeAdjustmentThreshold: Integer;
    FLargeAdjustmentThresholdUnits: Integer;
    FLargeAdjustmentAction: Integer;
    FServer: boolean;
    FOnStateChange: TNotifyEvent;
    FOnWarnAdj: TWarnAdjEvent;
    FOnExit: TNotifyEvent;
    FServerTime, FStationTime: TDateTime;
    FWarnAdjResult: boolean;
    FWantUpdateNow: boolean;
    FManualUpdate: boolean;
    FLastUpdateStatus: TSyncStatus;
    FDoingSync: boolean;

    FTimeToNextUpdate: integer;

    // FMinGoodServers: Integer;
    // FMaxDiscrepancy: Integer;
    FDemoteOnErrorCount: integer;
    FUpdateTrigger: string;

    FWindowsSuspending: boolean;
    FWindowsResumed: boolean;

    FResetTimeStatus: boolean;

    ServerIPC: TNetTimeIPCServer;

    RFC868_TCP_Thread: TRFC868_TCPServerThread;
    RFC868_UDP_Thread: TRFC868_UDPServerThread;
    NTP_Thread: TNTPServerThread;

    function GetServerStatus: TServerStatusBlock;
    procedure ExitNow;

  protected
    procedure DoStateChange;
    procedure DoWarnAdj;

  public
    function GetActive: boolean; override;
    function GetStatus: TSyncStatus; override;
    function GetDoingSync: boolean; override;
    function GetTimeToNextUpdate: integer; override;
    function GetLastUpdateTime: TDateTime; override;
    function GetLastSuccessfulUpdateTime: TDateTime; override;
    function GetLastUpdateAttemptTime: TDateTime; override;
    function GetStateChange: TNotifyEvent; override;
    procedure SetStateChange(const sc: TNotifyEvent); override;
    function GetWarnAdj: TWarnAdjEvent; override;
    procedure SetWarnAdj(const wa: TWarnAdjEvent); override;
    function GetOnExit: TNotifyEvent; override;
    procedure SetOnExit(const ex: TNotifyEvent); override;
    function GetServer: boolean; override;
    procedure SetServer(const sv: boolean); override;
    procedure SetConfig(const cfg: TServerConfigBlock); override;
    function GetConfig: TServerConfigBlock; override;
    procedure ForceUpdate; override;
    procedure TriggerUpdateNow; override;
    function UpdateNow: boolean; override;
    procedure KillEverything; override;
    procedure WindowsSuspending; override;
    procedure WindowsResuming; override;
    procedure Start(IPCServer: boolean = True);
    procedure Stop;

    constructor Create;
  end;

  TTimeThread = class(TThread)
  public
    dttime: TDateTime;
    NowOfLastUpdate: TDateTime;
    NowOfLastSuccessfulUpdate: TDateTime;
    NowOfLastUpdateAttempt: TDateTime;
    StatusOfLastUpdate: TSyncStatus;
    MyOwner: TNetTimeServer;
    procedure SetDateTime(dDateTime: TDateTime);
    constructor Create(const Suspended: boolean);
    destructor Destroy; override;
  private
    update_rejected: boolean;
    time_retrieval_time: TDateTime;
  protected
    procedure Execute; override;
  end;

  TTimeWatcher = class(TThread)
  public
    Synchronized: boolean;
    MyOwner: TNetTimeServer;
  protected
    procedure Execute; override;
  end;

var ServiceMode: Boolean = False;

implementation

uses iswinnt, timeconv, Registry, winerr, WinSockUtil;

constructor TNetTimeServer.Create;
begin
  inherited Create;
  FServerCount:= 0;
  FSyncFreq:= DefaultSyncFreq;
  FSyncFreqUnits:= DefaultSyncFreqUnits;
  FLostSync:= DefaultLostSync;
  FLostSyncUnits:= DefaultLostSyncUnits;
  FRetry:= DefaultRetry;
  FRetryUnits:= DefaultRetryUnits;
  FLargeAdjustmentThreshold:= DefaultLargeAdjustmentThreshold;
  FLargeAdjustmentThresholdUnits:= DefaultLargeAdjustmentThresholdUnits;
  FLargeAdjustmentAction:= DefaultLargeAdjustmentAction;
  FServer:= false;
  FOnStateChange:= nil;
  FOnWarnAdj:= nil;
  FDemoteOnErrorCount:= DefaultDemoteOnErrorCount;
end;

procedure TNetTimeServer.ForceUpdate;
begin
  // do nothing
end;

function TNetTimeServer.GetActive: boolean;
begin
  result:= FActive and (not ttime.Terminated);
end;

function TNetTimeServer.GetStateChange: TNotifyEvent;
begin
  result:= FOnStateChange;
end;

procedure TNetTimeServer.SetStateChange(const sc: TNotifyEvent);
begin
  FOnStateChange:= sc;
end;

function TNetTimeServer.GetWarnAdj: TWarnAdjEvent;
begin
  result:= FOnWarnAdj;
end;

procedure TNetTimeServer.SetWarnAdj(const wa: TWarnAdjEvent);
begin
  FOnWarnAdj:= wa;
end;

function TNetTimeServer.GetOnExit: TNotifyEvent;
begin
  result:= FOnExit;
end;

procedure TNetTimeServer.SetOnExit(const ex: TNotifyEvent);
begin
  FOnExit:= ex;
end;

procedure TNetTimeServer.SetConfig(const cfg: TServerConfigBlock);
begin
  FServerCount:= cfg.ServerCount;
  FServers:= cfg.Servers;
  FSyncFreq:= cfg.SyncFreq;
  FSyncFreqUnits:= cfg.SyncFreqUnits;
  FLostSync:= cfg.LostSync;
  FLostSyncUnits:= cfg.LostSyncUnits;
  FLargeAdjustmentThreshold:= cfg.LargeAdjustmentThreshold;
  FLargeAdjustmentThresholdUnits:= cfg.LargeAdjustmentThresholdUnits;
  FLargeAdjustmentAction:= cfg.LargeAdjustmentAction;
  FRetry:= cfg.Retry;
  FRetryUnits:= cfg.RetryUnits;

  // FMinGoodServers:= cfg.MinGoodServers;
  // FMaxDiscrepancy:= cfg.MaxDiscrepancy;
  FDemoteOnErrorCount:= cfg.DemoteOnErrorCount;

  Logging.LogLevel:= cfg.LogLevel;
  ntptime.AlwaysProvideTime:= cfg.AlwaysProvideTime;

  FResetTimeStatus:= True;
end;

function TNetTimeServer.GetConfig: TServerConfigBlock;
begin
  result.ServerCount:= FServerCount;
  result.Servers:= FServers;
  result.SyncFreq:= FSyncFreq;
  result.SyncFreqUnits:= FSyncFreqUnits;
  result.LostSync:= FLostSync;
  result.LostSyncUnits:= FLostSyncUnits;
  result.LargeAdjustmentThreshold:= FLargeAdjustmentThreshold;
  result.LargeAdjustmentThresholdUnits:= FLargeAdjustmentThresholdUnits;
  result.LargeAdjustmentAction:= FLargeAdjustmentAction;
  result.Retry:= FRetry;
  result.RetryUnits:= FRetryUnits;
  result.DemoteOnErrorCount:= FDemoteOnErrorCount;
  result.LogLevel:= Logging.LogLevel;
  result.AlwaysProvideTime:= ntptime.AlwaysProvideTime;
end;

function TNetTimeServer.GetLastUpdateTime: TDateTime;
begin
  if FActive then
    result:= (ttime as TTimeThread).NowOfLastUpdate
  else
    result:= 0;
end;

function TNetTimeServer.GetLastSuccessfulUpdateTime: TDateTime;
begin
  if FActive then
    result:= (ttime as TTimeThread).NowOfLastSuccessfulUpdate
  else
    result:= 0;
end;

function TNetTimeServer.GetLastUpdateAttemptTime: TDateTime;
begin
  if FActive then
    result:= (ttime as TTimeThread).NowOfLastUpdateAttempt
  else
    result:= 0;
end;

function TNetTimeServer.GetTimeToNextUpdate: integer;
begin
  if FActive then
    result:= FTimeToNextUpdate
  else
    result:= 0;
end;

function TNetTimeServer.GetStatus: TSyncStatus;
var
  i: integer;
begin
  if not FActive then
    begin
      result.Synchronized:= false;
      for i:= 0 to MaxServers - 1 do
        result.ServerDataArray[i].Status:= ssUnconfigured;
    end
  else
    result:= FLastUpdateStatus;
end;

function TNetTimeServer.GetDoingSync: boolean;
begin
  result:= FDoingSync;
end;

function TNetTimeServer.GetServer: boolean;
begin
  result:= FServer;
end;

procedure TNetTimeServer.SetServer(const sv: boolean);
begin
  if (FServer = sv) then
    exit;

  FServer:= sv;
  if FServer then
    begin
      RFC868_TCP_Thread:= TRFC868_TCPServerThread.Create(false, RFC868_Port);
      RFC868_UDP_Thread:= TRFC868_UDPServerThread.Create(false, RFC868_Port);
      NTP_Thread:= TNTPServerThread.Create(false, NTP_Port);
    end
  else
    begin
      RFC868_TCP_Thread.Terminate;
      RFC868_UDP_Thread.Terminate;
      NTP_Thread.Terminate;
    end;
end;

function TNetTimeServer.GetServerStatus: TServerStatusBlock;
begin
  result.Config:= GetConfig;
  result.Server:= GetServer;
  result.Active:= FActive;
  result.Status:= GetStatus;
  result.WantUpdate:= FWantUpdateNow;
  result.DoingSync:= GetDoingSync;
  result.LastUpdateTime:= GetLastUpdateTime;
  result.LastSuccessfulUpdateTime:= GetLastSuccessfulUpdateTime;
  result.LastUpdateAttemptTime:= GetLastUpdateAttemptTime;
  result.TimeToNextUpdate:= FTimeToNextUpdate;
end;

procedure TNetTimeServer.ExitNow;
begin
  if Assigned(FOnExit) then
    FOnExit(Self);
end;

procedure TNetTimeServer.TriggerUpdateNow;
begin
  FManualUpdate:= True;
  FWantUpdateNow:= True;
  FUpdateTrigger:= 'Manual Update';
end;

function TNetTimeServer.UpdateNow: boolean;
begin
  result:= false;

  TriggerUpdateNow;
  while FWantUpdateNow do
    begin
      Application.ProcessMessages;
      sleep(GUISleepTime);

      if Application.Terminated then
        exit;
    end;
  result:= FLastUpdateStatus.Synchronized;
end;


procedure TNetTimeServer.KillEverything;
begin
  if Assigned(ServerIPC) then
    ServerIPC.KillEverything;
end;

procedure TNetTimeServer.WindowsSuspending;
begin
  FWindowsSuspending:= True;
end;

procedure TNetTimeServer.WindowsResuming;
begin
  FWindowsResumed:= True;
end;

procedure TNetTimeServer.DoWarnAdj;
begin
  if Assigned(FOnWarnAdj) then
    FWarnAdjResult:= FOnWarnAdj(Self, FServerTime, FStationTime)
  else
    begin
      Assert(Assigned(ServerIPC));
      FWarnAdjResult:= ServerIPC.LargeAdjustWarn(FServerTime, FStationTime);
    end;
end;

procedure TNetTimeServer.DoStateChange;
begin
  if Assigned(FOnStateChange) then
    FOnStateChange(Self);

  if Assigned(ServerIPC) then
    ServerIPC.AdviseStatus;
end;

procedure TNetTimeServer.Start(IPCServer: boolean = True);
var
  tt: TTimeThread;
  tw: TTimeWatcher;
begin
  if FActive then
    exit;

  if IPCServer then
    begin
      ServerIPC:= TNetTimeIPCServer.Create(GetServerStatus, SetConfig, SetServer, ExitNow, TriggerUpdateNow);
      ServerIPC.InitResources;
    end;

  ttime:= TTimeThread.Create(True);
  tt:= (ttime as TTimeThread);
  tt.MyOwner:= Self;
  tt.Resume;
  ttwatch:= TTimeWatcher.Create(True);
  tw:= (ttwatch as TTimeWatcher);
  tw.MyOwner:= Self;
  tw.Resume;
  ntptime.TimeSyncGoodFunc:= GetSynchronized;
  ntptime.TimeLastUpdatedFunc:= GetLastSuccessfulUpdateTime;
  FActive:= True;
end;

procedure TNetTimeServer.Stop;
begin
  if not FActive then
    exit;

  if Assigned(ServerIPC) then
    sleep(IPCSleepTime);

  ntptime.TimeSyncGoodFunc:= nil;
  ntptime.TimeLastUpdatedFunc:= nil;
  if Assigned(ttwatch) then
    begin
      ttwatch.Terminate;
      ttwatch.WaitFor;
      ttwatch.Free;
    end;
  if Assigned(ttime) then
    begin
      ttime.Terminate;
      ttime.WaitFor;
      ttime.Free;
    end;

  if Assigned(ServerIPC) then
    ServerIPC.Free;

  FActive:= false;
end;

{ TTimeThread }

constructor TTimeThread.Create(const Suspended: boolean);
begin
  inherited Create(True);
  // nothing to initialize yet
  if not Suspended then
    Resume;
end;

destructor TTimeThread.Destroy;
begin
  inherited Destroy;
end;

procedure TTimeThread.SetDateTime(dDateTime: TDateTime);
var
  dSysTime: TSystemTime;
  buffer: DWord;
  tkp, tpko: TTokenPrivileges;
  hToken: THandle;

begin
  if IsWindowsNT then
    begin
      if not OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY, hToken) then
        exit;
      LookupPrivilegeValue(nil, 'SE_SYSTEMTIME_NAME', tkp.Privileges[0].Luid);
      tkp.PrivilegeCount:= 1;
      tkp.Privileges[0].Attributes:= SE_PRIVILEGE_ENABLED;
      if not AdjustTokenPrivileges(hToken, false, tkp, sizeof(tkp), tpko, buffer) then
        exit;
      CloseHandle(hToken);
    end;
  DateTimeToSystemTime(dDateTime, dSysTime);
  SetLocalTime(dSysTime);
end;

procedure TTimeThread.Execute;
var
  Time_Status: TSyncStatus;
  haveaddr, oldhaveaddr: boolean;

  LastTime: TDateTime;
  TimeNow: TDateTime;

  Msg: string;
  i: integer;

  NetworkActiveCount: integer;
  GuardTime: integer;
  TimeToNextUpdate: integer;

  MinErrorTimeOut: integer;
  MinErrorTimeOut2: integer;
  MinErrorTimeOutTmp: integer;

  MilliSeconds: Int64;
  LargeAdjustmentThresholdValue: Int64;
  TimeUpdateOK: Boolean;
  UpdateOnce: Boolean;
  TryOnce: Boolean;

  // ServerData: PServerData;

  function ThreadClosed: boolean;
  begin
    result:= Terminated or (not Assigned(MyOwner));
  end;

  procedure TriggerUpdate(Reason: string);
  begin
    if MyOwner.FWantUpdateNow then
      exit;

    MyOwner.FWantUpdateNow:= True;
    MyOwner.FUpdateTrigger:= Reason;
  end;

  function Pad(s: string; i: integer): string;
  begin
    while Length(s) < i do
      s:= s + ' ';
    if Length(s) > i then
      s:= Copy(s, 1, i);
    result:= s;
  end;

  Procedure ShutDown;
  begin
    if Assigned(MyOwner.ServerIPC) then
      Synchronize(MyOwner.ServerIPC.KillEverything);
    Terminate;
  end;

  Procedure AskUser;
  begin
    MyOwner.FServerTime:= dttime;
    MyOwner.FStationTime:= time_retrieval_time;
    Synchronize(MyOwner.DoWarnAdj);
    update_rejected:= not MyOwner.FWarnAdjResult;
  end;

begin
  LogMessage('NetTime Version '+GetCurrentFileVersionString+' Started: '+Iff(ServiceMode, 'Service Mode', 'Standalone Mode'));
  LogMessage('Logging Level: '+LogLevelToStr(LogLevel));

  ReturnValue:= 0;
  dttime:= 0;
  NowOfLastUpdate:= 0;
  if AlwaysProvideTime then
    NowOfLastSuccessfulUpdate:= Now
  else
    NowOfLastSuccessfulUpdate:= 0;
  NowOfLastUpdateAttempt:= 0;
  StatusOfLastUpdate.Synchronized:= false;
  time_retrieval_time:= 0;
  haveaddr:= HaveLocalAddress;
  NetworkActiveCount:= NetworkWakeupSeconds; // Don't bother waiting on the first update sync!
  MyOwner.FUpdateTrigger:= 'Initial Startup';

  UpdateOnce:= LowerCase(ParamStr(1)) = '/updateonce';
  TryOnce:= LowerCase(ParamStr(1)) = '/tryonce';

  repeat
    if not ThreadClosed then
      begin
        if MyOwner.FResetTimeStatus then
          begin
            FillChar(Time_Status, sizeof(Time_Status), 0);
            MyOwner.FResetTimeStatus:= false;
          end;

        MyOwner.FWindowsSuspending:= false;
        MyOwner.FWindowsResumed:= false;
        MyOwner.FDoingSync:= True;

        // Make sure that the network has been active for a minimum period before we do the time sync - it might take time before we can do DNS queries!

        if not haveaddr then
          begin
            NowOfLastUpdateAttempt:= Now;
            SetLastSyncError(Time_Status, lse_NetworkDown);
            for i:= 0 to MyOwner.FServerCount - 1 do
              SetSyncServerStatus(Time_Status.ServerDataArray[i], ssNotUsed);
          end
        else
          begin
            while NetworkActiveCount < NetworkWakeupSeconds do
              begin
                sleep(1000);
                Inc(NetworkActiveCount);
              end;

            if MyOwner.FManualUpdate then
              begin
                for i:= 0 to MyOwner.FServerCount - 1 do
                  Time_Status.ServerDataArray[i].ErrorTimeOut:= 0;
              end;

            try
              NowOfLastUpdateAttempt:= Now;
              FigureBestKnownTime(MyOwner.FServerCount, MyOwner.FServers, Time_Status, dttime,
                MyOwner.FDemoteOnErrorCount);
              time_retrieval_time:= Now;
            except
              Time_Status.Synchronized:= false;
            end;
            if Time_Status.Synchronized then
              begin
                TimeUpdateOK:= True;
                update_rejected:= false;
                if (MyOwner.FLargeAdjustmentAction <> laa_UpdateTime) then
                  begin
                    MilliSeconds:= MilliSecondsApart(Now, dttime);
                    LargeAdjustmentThresholdValue:= BaseAndUnitsToValue(MyOwner.FLargeAdjustmentThreshold, MyOwner.FLargeAdjustmentThresholdUnits);
                    if Abs(MilliSeconds) >= LargeAdjustmentThresholdValue then
                      begin
                        LogMessage('Large Time Offset: '+GetOffsetStr(MilliSeconds), log_Verbose);
                        case MyOwner.FLargeAdjustmentAction of
                          laa_DoNothing:
                            begin
                              if MyOwner.FManualUpdate then
                                AskUser
                              else
                                begin
                                  TimeUpdateOK:= False;
                                  Time_Status.Synchronized:= False;
                                  Time_Status.LastErrorTime:= Now;
                                  Time_Status.LastSyncError:= lse_AdjustmentTooLarge;
                                end;
                            end;
                          laa_AskUser: AskUser;
                          laa_Quit:    update_rejected:= True;
                        end;
                      end;
                  end;
                if update_rejected then
                  begin
                    LogMessage('Terminating.', log_Verbose);
                    ShutDown;
                    exit;
                  end
                else
                  begin
                    if TimeUpdateOK then
                      begin
                        SetDateTime(dttime + (Now - time_retrieval_time));
                        NowOfLastSuccessfulUpdate:= Now;
                      end;
                  end;
              end;
          end;

        NowOfLastUpdate:= Now;

        if Time_Status.Synchronized then
          begin
            Msg:= 'Time Updated: ' + GetOffsetStr(Time_Status.Offset);
            if UpdateOnce then
              begin
                LogMessage('Single Sync Successful.', log_Verbose);
                ShutDown;
                exit;
              end;
          end
        else
          Msg:= 'Time Sync Failed!';

        Msg:= Pad(Msg, 30) + MyOwner.FUpdateTrigger;
        LogMessage(Msg);

        if not Time_Status.Synchronized then
          LogMessage('Failure Reason: ' + LastSyncErrorToStr(Time_Status.LastSyncError));

        if TryOnce then
          begin
            LogMessage('Single Attempt Completed.', log_Verbose);
            ShutDown;
            exit;
          end;

        StatusOfLastUpdate:= Time_Status;
      end;
    MyOwner.FLastUpdateStatus:= Time_Status;
    MyOwner.FWantUpdateNow:= false;
    MyOwner.FManualUpdate:= false;
    if IsWindowsNT then
      SetProcessWorkingSetSize(GetCurrentProcess, $FFFFFFFF, $FFFFFFFF);

    MyOwner.FDoingSync:= false;

    LastTime:= Now;
    GuardTime:= MinGuardTime;

    if Time_Status.Synchronized then
      TimeToNextUpdate:= BaseAndUnitsToValue(MyOwner.FSyncFreq, MyOwner.FSyncFreqUnits) div MillisecondsPerSecond
    else
      TimeToNextUpdate:= BaseAndUnitsToValue(MyOwner.FRetry, MyOwner.FRetryUnits) div MillisecondsPerSecond;

    MinErrorTimeOut:= high(integer);
    MinErrorTimeOut2:= high(integer);

    // Make sure that we're not going to try while servers are still timing out.
    for i:= 0 to MyOwner.FServerCount - 1 do
      begin
        if Time_Status.ServerDataArray[i].ErrorTimeOut < MinErrorTimeOut2 then
          MinErrorTimeOut2:= Time_Status.ServerDataArray[i].ErrorTimeOut;

        if MinErrorTimeOut2 < MinErrorTimeOut then
          begin
            MinErrorTimeOutTmp:= MinErrorTimeOut;
            MinErrorTimeOut:= MinErrorTimeOut2;
            MinErrorTimeOut2:= MinErrorTimeOutTmp;
          end;
      end;

    if not Time_Status.Synchronized then
      begin
        // If the last error was because we got inconsistent answers, we should wait until we can try 2 servers at least!
        if Time_Status.LastSyncError = lse_InconsistentResponses then
          MinErrorTimeOut:= MinErrorTimeOut2;

        if TimeToNextUpdate < MinErrorTimeOut then
          TimeToNextUpdate:= MinErrorTimeOut;
      end;

    MyOwner.FTimeToNextUpdate:= TimeToNextUpdate;

    repeat
      sleep(1000); // Must be a second for the following calculations to work.
      oldhaveaddr:= haveaddr;
      haveaddr:= HaveLocalAddress;

      for i:= 0 to MyOwner.FServerCount - 1 do
        begin
          if Time_Status.ServerDataArray[i].ErrorTimeOut > 0 then
            Dec(Time_Status.ServerDataArray[i].ErrorTimeOut);
        end;

      TimeNow:= Now;

      if haveaddr then
        begin
          if NetworkActiveCount < NetworkWakeupSeconds then
            Inc(NetworkActiveCount);
        end
      else
        NetworkActiveCount:= 0;

      if SecondsApart(LastTime, TimeNow) < 0 then
        TriggerUpdate('Time went backwards!');

      if SecondsApart(LastTime, TimeNow) > 2 then
        begin
          if MyOwner.FWindowsSuspending then
            begin
              // Allow up to 30 seconds for Windows to actually suspend
              for i:= 1 to 300 do
                begin
                  if MyOwner.FWindowsResumed then
                    Break;

                  sleep(100);
                end;

              if not MyOwner.FWindowsResumed then
                LogMessage('Took too long to suspend - giving up on waiting!', log_Debug);
            end;

          if MyOwner.FWindowsResumed then
            begin
              LogMessage('Resumed from Suspend', log_Debug);
              TriggerUpdate('Resumed from Suspend');

              // Wait for Windows to report that the network has gone down:

              for i:= 1 to 100 do
                begin
                  haveaddr:= HaveLocalAddress;

                  if not haveaddr then
                    begin
                      NetworkActiveCount:= 0;
                      LogMessage('Network is down!', log_Debug);
                      Break;
                    end;

                  sleep(100);
                end;

              if not haveaddr then
                begin
                  // Now wait for the network to come back up!
                  for i:= 1 to 600 do
                    begin
                      haveaddr:= HaveLocalAddress;

                      if haveaddr then
                        begin
                          LogMessage('Network is back up!', log_Debug);
                          Break;
                        end;

                      sleep(100);
                    end;
                end;
            end
          else
            TriggerUpdate('Time jumped forward!');
        end;

      LastTime:= TimeNow;

      if (not oldhaveaddr) and (haveaddr) and (not Time_Status.Synchronized) then
        TriggerUpdate('Network became active');

      if MyOwner.FTimeToNextUpdate > 0 then
        Dec(MyOwner.FTimeToNextUpdate);

      if haveaddr and (MyOwner.FTimeToNextUpdate <= 0) then
        begin
          if Time_Status.Synchronized then
            TriggerUpdate('Regular Update')
          else
            TriggerUpdate('Retry');
        end;

      if GuardTime > 0 then
        Dec(GuardTime);

    until Self.Terminated or MyOwner.FManualUpdate or (MyOwner.FWantUpdateNow and (GuardTime <= 0));
  until (Self.Terminated);
  ReturnValue:= 1;
  LogMessage('NetTime Shut Down', log_Normal);
end;

{ TTimeWatcher }

procedure TTimeWatcher.Execute;

var
  oldUpdate: TDateTime;
  old_sync: boolean;

begin
  ReturnValue:= 0;
  oldUpdate:= 0;
  Synchronized:= false;
  repeat
    sleep(PollSleepTime);
    old_sync:= Synchronized;
    if SecondsApartAbs(Now, (MyOwner.ttime as TTimeThread).NowOfLastUpdate) <= (BaseAndUnitsToValue(MyOwner.FLostSync, MyOwner.FLostSyncUnits) / 1000) then
      Synchronized:= (MyOwner.ttime as TTimeThread).StatusOfLastUpdate.Synchronized
    else
      Synchronized:= false;
    if (Synchronized <> old_sync) or (oldUpdate <> (MyOwner.ttime as TTimeThread).NowOfLastUpdate) then
      begin
        Synchronize(MyOwner.DoStateChange);
        oldUpdate:= (MyOwner.ttime as TTimeThread).NowOfLastUpdate;
      end;
  until (Self.Terminated);
  ReturnValue:= 1;
end;

end.
