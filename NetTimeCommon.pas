{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit NetTimeCommon;

interface

uses Windows, Messages, Classes, SysUtils, timeconv, WinUtils;

const
  RFC868_Port = 37;
  NTP_Port = 123;
  MaxServers = 5;
  MaxServerList = 1000;
  MagicCookie = $1A34450B;
  ProtocolVersion = 6;
  ms = 1.0 / (24 * 60 * 60 * 1000);
  IPCSleepTime = 10;
  GUISleepTime = 100;
  PollSleepTime = 1000;

  NetworkWakeupSeconds = 5;
  NetworkWakeupTime = NetworkWakeupSeconds * 1000;

  MaxDifferenceFromLocalTime = 10000;
  MaxDifferenceBetweenServers = 1000;

type

  TTimeProto = (ttpNTP, ttpRFC868_TCP, ttpRFC868_UDP);

  TServerDef = record
    HostName: Shortstring;
    Protocol: TTimeProto;
    Port: integer;
  end;

  TServerDefArray = array [0 .. MaxServers - 1] of TServerDef;

  TServerConfigBlock = record
    ServerCount: integer;
    Servers: TServerDefArray;
    SyncFreq: integer;
    SyncFreqUnits: Integer;
    LostSync: integer;
    LostSyncUnits: Integer;
    LargeAdjustmentThreshold: Integer;
    LargeAdjustmentThresholdUnits: Integer;
    LargeAdjustmentAction: Integer;
    Retry: integer;
    RetryUnits: Integer;
    Protocol: TTimeProto;
    DemoteOnErrorCount: integer;
    LogLevel: integer;
    AlwaysProvideTime: Boolean;
  end;

  TWarnAdjEvent = function(const Sender: TObject; const ServerTime, StationTime: TDateTime): boolean of object;

  TSyncServerStatus = (ssUnconfigured, ssNotUsed, ssGood, ssFailed, ssWrong, ssNoIP, ssDuplicateIP, ssKoD);

const
  ssError = [ssFailed .. ssKoD];

type
  TLastSyncError = (lse_None, lse_NetworkDown, lse_AllFailed, lse_InsufficientResponses, lse_InconsistentResponses, lse_AdjustmentTooLarge);

type
  TServerData = record
    HostName: Shortstring;
    IPAddress: LongWord;
    Time: TDateTime;
    NetLag: TDateTime;
    Offset: Int64; // In milliseconds
    TimeLag: integer; // In milliseconds
    RetrievalTime: TDateTime;
    Status: TSyncServerStatus;
    Done: boolean;
    ErrorStatus: TSyncServerStatus;
    ErrorTimeOut: integer;
    ErrorCount: integer;
    LastErrorTimeOut: integer;
    LastErrorTime: TDateTime;
  end;

  PServerData = ^TServerData;
  TServerDataArray = array [0 .. MaxServerList - 1] of TServerData;
  PServerDataArray = ^TServerDataArray;
  TServerDataSort = (sdsByTime, sdsByNetlag, sdsByOffset);

  {
    TSyncStatus = record
    Synchronized: boolean;
    OffSet: Integer;
    ss: array[0..MaxServers-1] of TSyncServerStatus;
    OffSets: array[0..MaxServers - 1] of Integer;
    TimeLags: array[0..MaxServers - 1] of Integer;
    end;
  }

  TSyncStatus = record
    Synchronized: boolean;
    Offset: Int64;
    LastSyncError: TLastSyncError;
    LastErrorTime: TDateTime;
    ServerDataArray: TServerDataArray;
  end;

  TNetTimeServerBase = class
  public
    function GetActive: boolean; virtual; abstract;
    function GetStatus: TSyncStatus; virtual; abstract;
    function GetSynchronized: boolean; virtual;
    function GetDoingSync: boolean; virtual; abstract;
    function GetLastUpdateTime: TDateTime; virtual; abstract;
    function GetLastSuccessfulUpdateTime: TDateTime; virtual; abstract;
    function GetLastUpdateAttemptTime: TDateTime; virtual; abstract;
    function GetTimeToNextUpdate: integer; virtual; abstract;
    function GetStateChange: TNotifyEvent; virtual; abstract;
    procedure SetStateChange(const sc: TNotifyEvent); virtual; abstract;
    function GetWarnAdj: TWarnAdjEvent; virtual; abstract;
    procedure SetWarnAdj(const wa: TWarnAdjEvent); virtual; abstract;
    function GetOnExit: TNotifyEvent; virtual; abstract;
    procedure SetOnExit(const ex: TNotifyEvent); virtual; abstract;
    function GetServer: boolean; virtual; abstract;
    procedure SetServer(const sv: boolean); virtual; abstract;
    procedure SetConfig(const cfg: TServerConfigBlock); virtual; abstract;
    function GetConfig: TServerConfigBlock; virtual; abstract;
    procedure ForceUpdate; virtual; abstract; // forces a CONFIGURATION update
    procedure TriggerUpdateNow; virtual; abstract; // forces a TIME update
    function UpdateNow: boolean; virtual; abstract;
    procedure KillEverything; virtual; abstract;
    procedure WindowsSuspending; virtual; abstract;
    procedure WindowsResuming; virtual; abstract;

    property Active: boolean read GetActive;
    property Status: TSyncStatus read GetStatus;
    property DoingSync: boolean read GetDoingSync;
    property LastUpdateTime: TDateTime read GetLastUpdateTime;
    property LastSuccessfulUpdateTime: TDateTime read GetLastSuccessfulUpdateTime;
    property LastUpdateAttemptTime: TDateTime read GetLastUpdateAttemptTime;
    property TimeToNextUpdate: integer read GetTimeToNextUpdate;
    property OnStateChange: TNotifyEvent read GetStateChange write SetStateChange;
    property OnWarnAdj: TWarnAdjEvent read GetWarnAdj write SetWarnAdj;
    property OnExitNow: TNotifyEvent read GetOnExit write SetOnExit;
    property Server: boolean read GetServer write SetServer;
    property Config: TServerConfigBlock read GetConfig write SetConfig;
  end;

  EServerRunning = class(Exception)
  end;

const
  // Large Adjustment Actions
  laa_UpdateTime      = 0;
  laa_DoNothing       = 1;
  laa_AskUser         = 2;
  laa_Quit            = 3;

  laa_Default         = laa_UpdateTime;

  DefaultSyncFreq = 12;
  DefaultSyncFreqUnits = ui_Hours;
  DefaultLostSync = 24;
  DefaultLostSyncUnits = ui_Hours;
  DefaultRetry = 1;
  DefaultRetryUnits = ui_Minutes;
  DefaultLargeAdjustmentThreshold = 2;
  DefaultLargeAdjustmentThresholdUnits = ui_Minutes;
  DefaultLargeAdjustmentAction = laa_UpdateTime;
  DefaultProtocol = ttpNTP;

  DefaultDaysBetweenUpdateChecks = 7;

  // DefaultMinGoodServers = 3;
  // DefaultMaxDiscrepancy = 2000;
  DefaultDemoteOnErrorCount = 4;

  ProgramRegistryPath = 'Software\Subjective Software\NetTime';
  ExNameUI = 'NetTimeGHJM_UI';
  exGlobalPrefix = 'Global\';
  ExNameServerBase = 'NetTimeGHJM_Server';
  ExNameStandaloneBase = 'NetTimeGHJM_Standalone';
  ExNameUIShutdown = 'NetTimeShutdown';

  ShareMemNameBase = 'NetTimeGHJM_ShareMem';
  ServerEventNameBase = 'NetTimeGHJM_ServerEvent';
  ClientEventNameBase = 'NetTimeGHJM_ServerEvent';

  ExNameService = 'NetTimeSvc';
  ExNameServiceApp = 'NetTimeService.exe';

  MinSyncFreq = 60;   // seconds
  MinSyncFreqUnits = ui_Seconds;
  MinNTPPoolSyncFreq = 15;
  MinNTPPoolSyncFreqUnits = ui_Minutes;
  MinGuardTime = 15;  // seconds

  NormalErrorTimeOut = 60;
  KoDErrorTimeOut = 900;
  MaxErrorTimeOut = 86400; // 1 Day!

Function ExNameServer: String;
Function ExNameStandalone: String;
Function ShareMemName: String;
Function ServerEventName: String;
Function ClientEventName: String;

procedure SortServerData(const Arr: PServerDataArray; const Count: integer; const WhichSort: TServerDataSort;
  const Ascending: boolean = True);
function GetAverageTime(const Arr: PServerDataArray; const Count: integer): TDateTime;
function GetAverageOffset(const Arr: PServerDataArray; const Count: integer): Int64;
procedure NormalizeTimes(const Arr: PServerDataArray; const Count: integer);

function DefaultPortForProtocol(const Proto: TTimeProto): integer;
function WinExecAndWait(Path: PChar; Visibility: Word): integer;

function SyncServerStatusToStr(Status: TSyncServerStatus): string;
procedure SetSyncServerStatus(var ServerData: TServerData; Status: TSyncServerStatus);
function LastSyncErrorToStr(LastSyncError: TLastSyncError): string;
procedure SetLastSyncError(var SyncStatus: TSyncStatus; SyncError: TLastSyncError);

implementation

Function GetGlobalName(s: String): String;
begin
  if RunningOnWin2000 then
    Result:= ExGlobalPrefix + s
  else
    Result:= s;
end;

Function ExNameServer: String;
begin
  Result:= GetGlobalName(ExNameServerBase);
end;

Function ExNameStandalone: String;
begin
  Result:= GetGlobalName(ExNameStandaloneBase);
end;

Function ShareMemName: String;
begin
  Result:= GetGlobalName(ShareMemNameBase);
end;

Function ServerEventName: String;
begin
  Result:= GetGlobalName(ServerEventNameBase);
end;

Function ClientEventName: String;
begin
  Result:= GetGlobalName(ClientEventNameBase);
end;

function DefaultPortForProtocol(const Proto: TTimeProto): integer;
begin
  case Proto of
    ttpRFC868_UDP, ttpRFC868_TCP:
      result:= RFC868_Port;
    ttpNTP:
      result:= NTP_Port;
  else
    result:= 0;
  end;
end;

function WinExecAndWait(Path: PChar; Visibility: Word): integer;

var
  Msg: TMsg;
  lpExitCode: cardinal;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;

begin
  FillChar(StartupInfo, SizeOf(TStartupInfo), 0);
  with StartupInfo do
    begin
      cb:= SizeOf(TStartupInfo);
      dwFlags:= STARTF_USESHOWWINDOW or STARTF_FORCEONFEEDBACK;
      wShowWindow:= Visibility;
    end;
  if CreateProcess(nil, Path, nil, nil, False, NORMAL_PRIORITY_CLASS, nil, nil, StartupInfo, ProcessInfo) then
    begin
      repeat
        while PeekMessage(Msg, 0, 0, 0, pm_Remove) do
          begin
            if Msg.Message = wm_Quit then
              Halt(Msg.WParam);
            TranslateMessage(Msg);
            DispatchMessage(Msg);
          end;
        GetExitCodeProcess(ProcessInfo.hProcess, lpExitCode);
      until lpExitCode <> Still_Active;
      with ProcessInfo do
        begin
          CloseHandle(hThread);
          CloseHandle(hProcess);
        end;
      result:= 0;
    end
  else
    result:= GetLastError;
end;

procedure NormalizeTimes(const Arr: PServerDataArray; const Count: integer);
var
  CalcNow: TDateTime;
  i: integer;
begin
  if Count = 0 then
    raise Exception.create('Cannot normalize a list of zero length');
  CalcNow:= Now;
  for i:= 0 to Count - 1 do
    Arr[i].Time:= Arr[i].Time + (CalcNow - Arr[i].RetrievalTime);
end;

procedure SortServerData(const Arr: PServerDataArray; const Count: integer; const WhichSort: TServerDataSort;
  const Ascending: boolean = True);
var
  Done: boolean;
  i: integer;
  OutOfOrder: boolean;
  TmpData: TServerData;
  Index1, Index2: integer;
begin
  repeat
    Done:= True;
    for i:= 0 to Count - 2 do
      begin
        if Ascending then
          begin
            Index1:= i;
            Index2:= i + 1;
          end
        else
          begin
            Index1:= i + 1;
            Index2:= i;
          end;

        case WhichSort of
          sdsByTime:
            OutOfOrder:= Arr[Index1].Time > Arr[Index2].Time;
          sdsByNetlag:
            OutOfOrder:= Arr[Index1].NetLag > Arr[Index2].NetLag;
          sdsByOffset:
            OutOfOrder:= Arr[Index1].Offset > Arr[Index2].Offset;
        else
          OutOfOrder:= False;
        end;

        if OutOfOrder then
          begin
            TmpData:= Arr[i];
            Arr[i]:= Arr[i + 1];
            Arr[i + 1]:= TmpData;
            Done:= False;
          end;
      end;
  until Done;
end;

function GetAverageTime(const Arr: PServerDataArray; const Count: integer): TDateTime;
var
  BaseTime: TDateTime;
  TotalDiff: TDateTime;
  i: integer;
  First, Last: integer;
  TimeCount: integer;
begin
  Assert(Count >= 1);

  TotalDiff:= 0;

  First:= 0;
  Last:= Count - 1;

  if Count >= 3 then
    begin
      // Ignore the highest and lowest times!

      Inc(First);
      Dec(Last);
    end;

  BaseTime:= Arr[First].Time;
  TimeCount:= 1;

  for i:= First + 1 to Last do
    begin
      TotalDiff:= TotalDiff + Arr[i].Time - BaseTime;
      Inc(TimeCount);
    end;

  result:= BaseTime + (TotalDiff / TimeCount);
end;

function GetAverageOffset(const Arr: PServerDataArray; const Count: integer): Int64;
var
  Total: Int64;
  GoodCount: integer;
  i: integer;
begin
  result:= 0;
  Total:= 0;
  GoodCount:= 0;

  for i:= 0 to Count - 1 do
    begin
      // Ignore servers that aren't good, or are for the local time!
      if (Arr[i].Status = ssGood) and (Arr[i].IPAddress <> 0) then
        begin
          Total:= Total + Arr[i].Offset;
          Inc(GoodCount);
        end;
    end;

  if GoodCount > 0 then
    result:= Round(Total / GoodCount);
end;

function TNetTimeServerBase.GetSynchronized: boolean;
begin
  result:= GetStatus.Synchronized;
end;

function SyncServerStatusToStr(Status: TSyncServerStatus): string;
begin
  case Status of
    ssNotUsed:
      result:= 'Not Used';
    ssGood:
      result:= 'Good';
    ssFailed:
      result:= 'Failed';
    ssWrong:
      result:= 'Wrong';
    ssNoIP:
      result:= 'Unable to Resolve';
    ssDuplicateIP:
      result:= 'Duplicate IP';
    ssKoD:
      result:= 'Kiss of Death!';
    ssUnconfigured:
      result:= 'Not Configured';
  else
    result:= 'Unknown';
  end;
end;

procedure SetSyncServerStatus(var ServerData: TServerData; Status: TSyncServerStatus);
begin
  ServerData.Status:= Status;

  if Status = ssGood then
    begin
      ServerData.ErrorCount:= 0;
      ServerData.ErrorStatus:= ssNotUsed;
      ServerData.LastErrorTimeOut:= 0;
      exit;
    end;

  if not(Status in [ssGood, ssNotUsed, ssUnconfigured]) then
    begin
      Inc(ServerData.ErrorCount);
      ServerData.ErrorStatus:= Status;
      ServerData.LastErrorTime:= Now;

      if Status = ssKoD then
        ServerData.ErrorTimeOut:= KoDErrorTimeOut
      else
        ServerData.ErrorTimeOut:= NormalErrorTimeOut;

      if ServerData.ErrorTimeOut < (2 * ServerData.LastErrorTimeOut) then
        ServerData.ErrorTimeOut:= 2 * ServerData.LastErrorTimeOut;

      if ServerData.ErrorTimeOut > MaxErrorTimeOut then
        ServerData.ErrorTimeOut:= MaxErrorTimeOut;

      ServerData.LastErrorTimeOut:= ServerData.ErrorTimeOut;
    end;
end;

function LastSyncErrorToStr(LastSyncError: TLastSyncError): string;
begin
  case LastSyncError of
    lse_None:
      result:= 'None';
    lse_NetworkDown:
      result:= 'Network Down';
    lse_AllFailed:
      result:= 'All Servers Failed';
    lse_InsufficientResponses:
      result:= 'Insufficient Responses';
    lse_InconsistentResponses:
      result:= 'Inconsistent Responses';
    lse_AdjustmentTooLarge:
      result:= 'Adjustment too large';
  else
    result:= 'Unknown';
  end;
end;

procedure SetLastSyncError(var SyncStatus: TSyncStatus; SyncError: TLastSyncError);
begin
  SyncStatus.Synchronized:= False;
  SyncStatus.LastSyncError:= SyncError;
  SyncStatus.LastErrorTime:= Now;
end;

end.
