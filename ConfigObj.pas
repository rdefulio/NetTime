{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit ConfigObj;

interface

uses SysUtils, timewrap, NetTimeCommon, IsWinNT, WinSvc, Math, Logging, cwinsvc, timeconv, UpdateCheck;

type
  TConfigObj = class
  private
    FServerCount: integer;
    FServers: TServerDefArray;
    FSyncFreq: integer;
    FSyncFreqUnits: Integer;
    FLostSync: integer;
    FLostSyncUnits: Integer;
    FLargeAdjustmentThreshold: Integer;
    FLargeAdjustmentThresholdUnits: Integer;
    FLargeAdjustmentAction: Integer;
    FRetry: integer;
    FRetryUnits: Integer;
    FServer: boolean;
    FAlwaysProvideTime: Boolean;
    FLoadOnLogin: boolean;
    FServiceOnBoot: boolean;

    FDemoteOnErrorCount: integer;
    FLogLevel: integer;

    function GetServer(idx: integer): TServerDef;
  public
    constructor Create;
    procedure SetDefaultsAndMinSettings;
    procedure ReadFromRegistry;
    procedure ReadFromRunning(tt: TNetTimeServerBase);
    procedure WriteToRegistry;
    procedure WriteToRunning(tt: TNetTimeServerBase);
    Function GetLargeAdjustmentThresholdValue: Int64;

    property ServerCount: integer read FServerCount;
    property Servers[idx: integer]: TServerDef read GetServer;
    property SyncFreq: integer read Fsyncfreq write FSyncFreq;
    property SyncFreqUnits: Integer read FSyncFreqUnits write FSyncFreqUnits;
    property LostSync: integer read Flostsync write Flostsync;
    property LostSyncUnits: Integer read FLostSyncUnits write FLostSyncUnits;
    property LargeAdjustmentThreshold: Integer read FLargeAdjustmentThreshold write FLargeAdjustmentThreshold;
    property LargeAdjustmentThresholdUnits: Integer read FLargeAdjustmentThresholdUnits write FLargeAdjustmentThresholdUnits;
    property FLargeAdjustmentThresholdValue: Int64 read GetLargeAdjustmentThresholdValue;
    property LargeAdjustmentAction: Integer read FLargeAdjustmentAction write FLargeAdjustmentAction;
    property Retry: integer read Fretry write Fretry;
    property RetryUnits: Integer read FRetryUnits write FRetryUnits;
    property Server: boolean read Fserver write Fserver;
    property AlwaysProvideTime: Boolean read FAlwaysProvideTime write FAlwaysProvideTime;
    property LoadOnLogin: boolean read Floadonlogin write Floadonlogin;
    property ServiceOnBoot: boolean read Fserviceonboot write Fserviceonboot;

    // property MinGoodServers: Integer read FMinGoodServers write FMinGoodServers;
    // property MaxDiscrepancy: Integer read FMaxDiscrepancy write FMaxDiscrepancy;
    property DemoteOnErrorCount: integer read FDemoteOnErrorCount write FDemoteOnErrorCount;
    property LogLevel: integer read FLogLevel write FLogLevel;

    procedure ClearServerList;
    procedure AddServer(const Srv: TServerDef);
  end;

procedure SetAutoStart(AutoStart: boolean);
procedure InstallNetTimeService(AutoStart: boolean);
procedure UninstallNetTimeService;

implementation

uses windows, registry;

function FindExe(const exefn: string): string;

var
  dir: string;
  di: TSearchRec;
  found: boolean;

begin
  dir:= ExtractFilePath(ExpandFileName(ParamStr(0)));
  found:= (FindFirst(dir + exefn, faAnyFile, di) = 0);
{$WARNINGS OFF} FindClose(di.FindHandle); {$WARNINGS ON}
  if found then
    result:= dir + di.Name
  else
    begin
      result:= '';
      raise exception.Create('Could not locate ' + exefn);
    end;
end;

procedure SetAutoStart(AutoStart: boolean);
var
  reg: TRegistry;
begin
  reg:= TRegistry.Create;
  reg.RootKey:= HKEY_LOCAL_MACHINE;
  if reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', true) then
    begin
      if AutoStart then
        reg.WriteString('NetTime', FindExe('NetTime.exe'))
      else
        reg.DeleteValue('NetTime');
    end;
  reg.CloseKey;
  reg.Free;
end;

procedure InstallNetTimeService(AutoStart: boolean);
var
  sch, svh: THandle;
  s: string;
  WinExecResult: Integer;

  // There is a bug in the VCL (at least in Delphi 7) where it doesn't
  // include quotes around the path to the service executable.
  // This can cause a problem if the ambiguity caused by the lack of quotes
  // leads Windows to match a different file instead of the one that we want.
  // e.g. C:\Program Files\NetTime\NetTimeService.exe would match with C:\Program.exe if it exists.

  // I've fixed the VCL source in my own copy, but I've included the code below in case anyone else
  // is compiling with a broken VCL. 
  Procedure FixServiceImagePath;
  var Path: String;
      reg: TRegistry;
  begin
    Reg:= TRegistry.Create;
    reg.RootKey:= HKEY_LOCAL_MACHINE;
    if reg.OpenKey('System\CurrentControlSet\Services\'+ExNameService, False) then
      begin
        Path:= reg.ReadString('ImagePath');
        if Copy(Path, 1, 1) <> '"' then
          begin
            Path:= '"' + Path + '"';
            reg.WriteString('ImagePath', Path);
          end;
      end;
    reg.CloseKey;
    reg.Free;
  end;

begin
  if not IsWindowsNT then
    exit;

  sch:= OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if sch = 0 then
    raise exception.Create('Could not open service control manager'#13#13'Error: ' + SysErrorMessage(GetLastError));

  svh:= OpenService(sch, ExNameService, SERVICE_ALL_ACCESS);

  if svh = 0 then
    begin
      s:= '"' + FindExe(ExNameServiceApp) + '" /install /silent';
      WinExecResult:= WinExecAndWait(pchar(s), SW_SHOW);
      if WinExecResult <> 0 then
        raise exception.Create('Error installing NetTime Service'#13#13'Error: ' + SysErrorMessage(WinExecResult)+#13#13+
                               'Command Line: '+#13#13+s);

      FixServiceImagePath;

      svh:= OpenService(sch, ExNameService, SERVICE_ALL_ACCESS);
    end;

  if svh = 0 then
    raise exception.Create('Could not open NetTime service'#13#13'Error: ' + SysErrorMessage(GetLastError));

  if not ChangeServiceConfig(svh, SERVICE_NO_CHANGE, IfThen(AutoStart, SERVICE_AUTO_START, SERVICE_DEMAND_START),
    SERVICE_NO_CHANGE, nil, nil, nil, nil, nil, nil, nil) then
    raise exception.Create('Could not update service configuration. '#13#13'Error: ' + SysErrorMessage(GetLastError));
    
  CloseServiceHandle(svh);
  CloseServiceHandle(sch);
end;

procedure UninstallNetTimeService;
var
  sch: THandle;
  svh: THandle;
begin
  if not IsWindowsNT then
    exit;

  sch:= OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if sch <> 0 then
    begin
      svh:= OpenService(sch, ExNameService, SERVICE_ALL_ACCESS);
      if sch <> 0 then
        DeleteService(svh);
    end;
end;

constructor TConfigObj.Create;
begin
  inherited Create;
  FServerCount:= 0;
  Fsyncfreq:= DefaultSyncFreq;
  FSyncFreqUnits:= DefaultSyncFreqUnits;
  Flostsync:= DefaultLostSync;
  FLostSyncUnits:= DefaultLostSyncUnits;
  Fretry:= DefaultRetry;
  FRetryUnits:= DefaultRetryUnits;
  FLargeAdjustmentThreshold:= DefaultLargeAdjustmentThreshold;
  FLargeAdjustmentThresholdUnits:= DefaultLargeAdjustmentThresholdUnits;
  FLargeAdjustmentAction:= laa_Default;
  Fserver:= false;
  FAlwaysProvideTime:= False;
  Floadonlogin:= false;
  Fserviceonboot:= false;

  FDemoteOnErrorCount:= DefaultDemoteOnErrorCount;

  FLogLevel:= DefaultLogLevel;
end;

procedure TConfigObj.SetDefaultsAndMinSettings;
var i: integer;
    MinimumSyncFreq: Integer;
    MinimumSyncFreqUnits: Integer;
begin
  if FServerCount = 0 then
    begin
      for i:= 0 to 3 do
        begin
          FServers[i].Hostname:= IntToStr(i) + '.nettime.pool.ntp.org';
          FServers[i].Protocol:= ttpNTP;
          FServers[i].Port:= NTP_Port;
        end;

      FServerCount:= 4;
    end;

  MinimumSyncFreq:= MinSyncFreq;
  MinimumSyncFreqUnits:= MinSyncFreqUnits;

  for i:= 0 to FServerCount - 1 do
    begin
      if Pos('pool.ntp.org', LowerCase(FServers[i].Hostname)) > 0 then
        begin
          MinimumSyncFreq:= MinNTPPoolSyncFreq;
          MinimumSyncFreqUnits:= MinNTPPoolSyncFreqUnits;
          Break;
        end;
    end;

  if BaseAndUnitsToValue(Fsyncfreq, FSyncFreqUnits) < BaseAndUnitsToValue(MinimumSyncFreq, MinimumSyncFreqUnits) then
    begin
      Fsyncfreq:= MinimumSyncFreq;
      FSyncFreqUnits:= MinimumSyncFreqUnits;
    end;

  if BaseAndUnitsToValue(Fretry, FRetryUnits) < BaseAndUnitsToValue(MinSyncFreq, MinSyncFreqUnits) then
    begin
      FRetry:= MinSyncFreq;
      FRetryUnits:= MinSyncFreqUnits;
    end;

  if BaseAndUnitsToValue(Fretry, FRetryUnits) > BaseAndUnitsToValue(Fsyncfreq, FSyncFreqUnits) then
    begin
      Fretry:= Fsyncfreq;
      FRetryUnits:= FSyncFreqUnits;
    end;
end;

procedure TConfigObj.ReadFromRegistry;
var
  reg: TRegistry;
  i: integer;
  s: string;
  sch, svh: THandle;
  qsc: QUERY_SERVICE_CONFIG;
  qbn: cardinal;

  Function ReadString(Name: String; Default: String): String;
  begin
    try
      Result:= reg.ReadString(Name);
    except
      Result:= Default;
    end;
  end;

  Function ReadInteger(Name: String; Default: Integer): Integer;
  begin
    try
      Result:= reg.ReadInteger(Name);
    except
      Result:= Default;
    end;
  end;

  Function ReadBool(Name: String; Default: Boolean): Boolean;
  begin
    try
      Result:= reg.ReadBool(Name);
    except
      Result:= Default;
    end;
  end;

  procedure GetServerInfo(const n: integer);
  var sd: TServerDef;
      hns: string;
  begin
    if n = 0 then
      hns:= ''
    else
      hns:= IntToStr(n);

    sd.Hostname:= ReadString('Hostname' + hns, '');

    if sd.Hostname <> '' then
      begin
        sd.Protocol:= TTimeProto(ReadInteger('Protocol' + hns, Integer(ttpRFC868_TCP)));
        sd.Port:= ReadInteger('Port' + hns, DefaultPortForProtocol(sd.Protocol));
        FServers[FServerCount]:= sd;
        inc(FServerCount);
      end;
  end;

  Procedure ReadValueWithBaseAndUnits(Name: String; var Base: Integer; var Units: Integer; DefaultBase: Integer; DefaultUnits: Integer);
  begin
    Base:= ReadInteger(Name, DefaultBase);

    if Reg.ValueExists(Name) and (not Reg.ValueExists(Name+'Units')) then
      ValueToBaseAndUnits(Base * MillisecondsPerSecond, Base, Units)
    else
      Units:= ReadInteger(Name+'Units', DefaultUnits);
  end;

begin
  reg:= TRegistry.Create;
  reg.RootKey:= HKEY_LOCAL_MACHINE;
  if reg.OpenKeyReadOnly(ProgramRegistryPath) then
    begin
      for i:= 0 to MaxServers - 1 do
        GetServerInfo(i);

      ReadValueWithBaseAndUnits('SyncFreq', FSyncFreq, FSyncFreqUnits, DefaultSyncFreq, DefaultSyncFreqUnits);
      ReadValueWithBaseAndUnits('LostSync', FLostSync, FLostSyncUnits, Defaultlostsync, DefaultLostSyncUnits);

      // Read the old value if necessary!
      if (not reg.ValueExists('LargeAdjustmentThreshold')) and (reg.ValueExists('WarnAdj')) then
        begin
          ValueToBaseAndUnits(ReadInteger('WarnAdj', DefaultLargeAdjustmentThreshold)*MillisecondsPerSecond,
                              FLargeAdjustmentThreshold,
                              FLargeAdjustmentThresholdUnits);

          if LargeAdjustmentThreshold > 0 then
            LargeAdjustmentAction:=            laa_AskUser
          else
            LargeAdjustmentAction:=            laa_UpdateTime;
        end
      else
        begin
          LargeAdjustmentThreshold:=           ReadInteger('LargeAdjustmentThreshold', DefaultLargeAdjustmentThreshold);
          LargeAdjustmentThresholdUnits:=      ReadInteger('LargeAdjustmentThresholdUnits', DefaultLargeAdjustmentThresholdUnits);
          LargeAdjustmentAction:=              ReadInteger('LargeAdjustmentAction', DefaultLargeAdjustmentAction);
        end;

      ReadValueWithBaseAndUnits('Retry', FRetry, FRetryUnits, DefaultRetry, DefaultRetryUnits);
      Server:=                             ReadBool('Server', False);
      if Server then
        AlwaysProvideTime:=                ReadBool('AlwaysProvideTime', False)
      else
        AlwaysProvideTime:=                False;
        
      DemoteOnErrorCount:=                 ReadInteger('DemoteOnErrorCount', DefaultDemoteOnErrorCount);
      LogLevel:=                           ReadInteger('LogLevel', DefaultLogLevel);
      Logging.LogLevel:=                   LogLevel;
    end;

  reg.CloseKey;

  if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Run') then
    begin
      s:= ReadString('NetTime', '');
      Floadonlogin:= (s <> '');
    end;
  reg.CloseKey;
  if IsWindowsNT then
    begin
      sch:= OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
      if sch = 0 then
        Fserviceonboot:= false
      else
        begin
          // svh := OpenService(sch,'NetTimeSvc',SERVICE_ALL_ACCESS);
          // 25/4/2011: Changed this to SERVICE_QUERY_CONFIG from SERVICE_ALL_ACCESS so that when running under limited access, can still check the config!
          svh:= OpenService(sch, ExNameService, SERVICE_QUERY_CONFIG);
          if svh = 0 then
            Fserviceonboot:= false
          else
            begin
              QueryServiceConfig(svh, @qsc, SizeOf(qsc), qbn);
              if (qsc.dwStartType = SERVICE_AUTO_START) then
                Fserviceonboot:= true
              else
                Fserviceonboot:= false;
            end;
          CloseServiceHandle(svh);
        end;
      CloseServiceHandle(sch);
    end;
  reg.Free;

  SetDefaultsAndMinSettings;
end;

procedure TConfigObj.ReadFromRunning(tt: TNetTimeServerBase);
var cfg: TServerConfigBlock;
begin
  cfg:= tt.GetConfig;
  FServerCount:= cfg.ServerCount;
  FServers:= cfg.Servers;
  Fsyncfreq:= cfg.SyncFreq;
  FSyncFreqUnits:= cfg.SyncFreqUnits;
  Flostsync:= cfg.LostSync;
  FLostSyncUnits:= cfg.LostSyncUnits;
  FLargeAdjustmentThreshold:= cfg.LargeAdjustmentThreshold;
  FLargeAdjustmentThresholdUnits:= cfg.LargeAdjustmentThresholdUnits;
  FLargeAdjustmentAction:= cfg.LargeAdjustmentAction;
  Fretry:= cfg.Retry;
  FRetryUnits:= cfg.RetryUnits;
  FAlwaysProvideTime:= cfg.AlwaysProvideTime;

  FDemoteOnErrorCount:= cfg.DemoteOnErrorCount;

  Fserver:= tt.Server;
end;

procedure TConfigObj.WriteToRegistry;
var
  reg: TRegistry;
  i: integer;

  procedure WriteServer(const n: integer);
  var
    hns: string;
  begin
    if n = 0 then
      hns:= ''
    else
      hns:= IntToStr(n);
    if (n < ServerCount) then
      begin
        reg.WriteString('Hostname' + hns, Servers[n].Hostname);
        reg.WriteInteger('Protocol' + hns, integer(Servers[n].Protocol));
        reg.WriteInteger('Port' + hns, Servers[n].Port);
      end
    else
      begin
        reg.DeleteValue('Hostname' + hns);
        reg.DeleteValue('Protocol' + hns);
        reg.DeleteValue('Port' + hns);
      end;
  end;

begin
  reg:= TRegistry.Create;
  reg.RootKey:= HKEY_LOCAL_MACHINE;
  if reg.OpenKey(ProgramRegistryPath, true) then
    begin
      for i:= 0 to MaxServers - 1 do
        WriteServer(i);
      reg.WriteInteger('SyncFreq', SyncFreq);
      reg.WriteInteger('SyncFreqUnits', SyncFreqUnits);
      reg.WriteInteger('LostSync', LostSync);
      reg.WriteInteger('LostSyncUnits', LostSyncUnits);
      reg.WriteInteger('LargeAdjustmentThreshold', LargeAdjustmentThreshold);
      reg.WriteInteger('LargeAdjustmentThresholdUnits', LargeAdjustmentThresholdUnits);
      reg.WriteInteger('LargeAdjustmentAction', LargeAdjustmentAction);
      reg.WriteInteger('Retry', Retry);
      reg.WriteInteger('RetryUnits', RetryUnits);
      reg.WriteBool('Server', Server);
      reg.WriteBool('AlwaysProvideTime', AlwaysProvideTime);
      reg.WriteInteger('DemoteOnErrorCount', DemoteOnErrorCount);
      reg.WriteInteger('LogLevel', FLogLevel);

      if Logging.LogLevel <> FLogLevel then
        begin
          Logging.LogLevel:= FLogLevel;
          LogMessage('New Logging Level: '+LogLevelToStr(LogLevel));
        end;
    end;
  reg.CloseKey;
  SetAutoStart(LoadOnLogin);
  InstallNetTimeService(Fserviceonboot);
  reg.Free;
end;

procedure TConfigObj.WriteToRunning(tt: TNetTimeServerBase);
var cfg: TServerConfigBlock;
begin
  cfg.ServerCount:= FServerCount;
  cfg.Servers:= FServers;
  cfg.SyncFreq:= SyncFreq;
  cfg.SyncFreqUnits:= SyncFreqUnits;
  cfg.LostSync:= LostSync;
  cfg.LostSyncUnits:= LostSyncUnits;
  cfg.LargeAdjustmentThreshold:= LargeAdjustmentThreshold;
  cfg.LargeAdjustmentThresholdUnits:= LargeAdjustmentThresholdUnits;
  cfg.LargeAdjustmentAction:= LargeAdjustmentAction;
  cfg.Retry:= Retry;
  cfg.RetryUnits:= RetryUnits;
  cfg.DemoteOnErrorCount:= DemoteOnErrorCount;
  cfg.LogLevel:= LogLevel;
  cfg.AlwaysProvideTime:= AlwaysProvideTime;

  tt.SetConfig(cfg);
  tt.Server:= Server;
end;

function TConfigObj.GetServer(idx: integer): TServerDef;
begin
  result:= FServers[idx];
end;

procedure TConfigObj.ClearServerList;
begin
  FServerCount:= 0;
end;

procedure TConfigObj.AddServer(const Srv: TServerDef);
begin
  FServers[FServerCount]:= Srv;
  inc(FServerCount);
end;

Function TConfigObj.GetLargeAdjustmentThresholdValue: Int64;
begin
  result:= BaseAndUnitsToValue(LargeAdjustmentThreshold, LargeAdjustmentThresholdUnits);
end;

end.
