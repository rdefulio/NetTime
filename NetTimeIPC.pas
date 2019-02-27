{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit NetTimeIPC;

interface

uses Windows, Forms, Classes, SysUtils, NetTimeCommon, iswinnt, syncobjs, WinUtils, Logging;

type

  TServerStatusBlock = record
    Config: TServerConfigBlock;
    Server: boolean;
    AlwaysProvideTime: Boolean;
    Active: boolean;
    Status: TSyncStatus;
    WantUpdate: boolean;
    DoingSync: boolean;
    LastUpdateTime: TDateTime;
    LastSuccessfulUpdateTime: TDateTime;
    LastUpdateAttemptTime: TDateTime;
    TimeToNextUpdate: Integer;
  end;

  // Whenever you change this, you have to increment ProtocolVersion
  // in NetTimeCommon.
  TShareMemBlock = record
    // Section that anyone can write to
    G_MagicCookie: longword;
    G_ProtocolVersion: longword;
    // G_ExitNowFlag: boolean;  // 25/4/2011: Removed by MTG so that limited users can't kill the service!
    // Section that the SERVER writes to
    S_ServerPID: longword;
    S_StatusProvidedSerial: Integer;
    S_AdviseStatusFlag: boolean;
    S_Status: TServerStatusBlock;
    S_LargeAdjFlag: boolean;
    S_ServerTime, S_StationTime: TDateTime;
    // S_LastUpdateGood: boolean; // only valid when C_WantUpdateNow called
    // Section that the CLIENT writes to
    C_ClientPID: longword;
    C_ClientStatusChangeFlag: boolean;
    C_StatusWantedSerial: Integer;
    C_LargeAdjReplyFlag: boolean;
    C_LargeAdjReplyResult: boolean;
    C_SetConfigFlag: boolean;
    C_Config: TServerConfigBlock;
    C_SetServerFlag: boolean;
    C_Server: boolean;
    C_AlwaysProvideTime: Boolean;
    C_WantUpdateNowFlag: boolean;
  end;

  PShareMemBlock = ^TShareMemBlock;

  TExitNowCallback = procedure of object;
  TUpdateNowCallback = procedure of object;

  TNetTimeIPC = class
  protected
    ShareMemHandle: THandle;
    ShareMem: PShareMemBlock;
    ExitNowCallback: TExitNowCallback;
  protected
    HaveKilled: boolean;
  public
    procedure InitResources; virtual;
    procedure FreeResources; virtual;
    function CheckServerRunning: boolean;
    function CheckClientRunning: boolean;
    procedure KillEverything;
    constructor Create(const enb: TExitNowCallback);
    destructor Destroy; override;
  end;

  TGetServerStatusCallback = function: TServerStatusBlock of object;
  TSetConfigCallback = procedure(const cfg: TServerConfigBlock) of object;
  TSetServerCallback = procedure(const srv: boolean) of object;

  TNetTimeServerThread = class;

  TNetTimeIPCServer = class(TNetTimeIPC)
  private
    MyThread: TNetTimeServerThread;
    ClientEvent: THandle;
    GetServerStatusCallback: TGetServerStatusCallback;
    SetConfigCallback: TSetConfigCallback;
    SetServerCallback: TSetServerCallback;
    UpdateNowCallback: TUpdateNowCallback;
    procedure ClientHello;
    procedure ClientGoodbye;
    procedure SetServer;
    procedure SetConfig;
  public
    procedure InitResources; override;
    procedure FreeResources; override;
    function LargeAdjustWarn(const ServerTime, StationTime: TDateTime): boolean;
    procedure AdviseStatus;
    constructor Create(const gsb: TGetServerStatusCallback; const scb: TSetConfigCallback;
      const ssb: TSetServerCallback; const enb: TExitNowCallback; const unb: TUpdateNowCallback);
    destructor Destroy; override;
  end;

  TNetTimeServerThread = class(TThread)
  protected
    MyOwner: TNetTimeIPCServer;
    MyEvent: THandle;
    procedure Execute; override;
  public
    constructor Create(const Owner: TNetTimeIPCServer; const Suspended: boolean = false);
  end;

  TAdviseStatusCallback = procedure(const stat: TServerStatusBlock) of object;
  TLargeAdjCallback = function(const ServerTime, StationTime: TDateTime): boolean of object;

  TNetTimeClientThread = class;

  TNetTimeIPCClient = class(TNetTimeIPC)
  private
    MyThread: TNetTimeClientThread;
    ServerEvent: THandle;
    AdviseStatusCallback: TAdviseStatusCallback;
    LargeAdjCallback: TLargeAdjCallback;
    procedure RetrieveStatus;
    procedure DoLargeAdj;
  public
    procedure InitResources; override;
    procedure FreeResources; override;
    function GetServerStatus: TServerStatusBlock;
    procedure SetConfig(const cfg: TServerConfigBlock);
    procedure SetServer(const srv: boolean);
    constructor Create(const asb: TAdviseStatusCallback; const lab: TLargeAdjCallback; const enb: TExitNowCallback);
    procedure TriggerUpdateNow;
    function UpdateNow: boolean;
    destructor Destroy; override;
  end;

  TNetTimeClientThread = class(TThread)
  protected
    MyOwner: TNetTimeIPCClient;
    MyEvent: THandle;
    procedure Execute; override;
  public
    constructor Create(const Owner: TNetTimeIPCClient; const Suspended: boolean = false);
  end;

implementation

  { TNetTimeIPC }

procedure TNetTimeIPC.InitResources;

var
  sa: TSecurityAttributes;
  sd: TSecurityDescriptor;
  sp: PSecurityAttributes;
  ae: boolean;

begin
  if IsWindowsNT then
    begin
      InitializeSecurityDescriptor(@sd, SECURITY_DESCRIPTOR_REVISION);
      SetSecurityDescriptorDACL(@sd, true, nil, false);
      sa.nLength:= sizeof(sa);
      sa.lpSecurityDescriptor:= @sd;
      sa.bInheritHandle:= false;
      sp:= @sa;
    end
  else
    sp:= nil;
  ShareMemHandle:= CreateFileMapping($FFFFFFFF, sp, PAGE_READWRITE, 0, sizeof(TShareMemBlock), PChar(ShareMemName));
  if ShareMemHandle = 0 then
    raise exception.Create('Could not open shared memory');
  ae:= (GetLastError = ERROR_ALREADY_EXISTS);
  ShareMem:= MapViewOfFile(ShareMemHandle, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(TShareMemBlock));
  if ShareMem = nil then
    raise exception.Create('Could not map shared memory');
  if not ae then
    FillChar(ShareMem^, sizeof(TShareMemBlock), 0);
end;

procedure TNetTimeIPC.FreeResources;
begin
  if ShareMem <> nil then
    begin
      UnmapViewOfFile(ShareMem);
      CloseHandle(ShareMemHandle);
      ShareMem:= nil;
    end;
end;

function CheckProcessExists(const pid: longword): boolean;

var
  ph: THandle;
  er: longword;

begin
  if pid = 0 then
    begin
      result:= false;
      exit;
    end;
  ph:= OpenProcess(PROCESS_QUERY_INFORMATION, false, pid);
  if ph = 0 then
    begin
      er:= GetLastError;
      if (er = ERROR_ACCESS_DENIED) or (er = ERROR_NETWORK_ACCESS_DENIED) or (er = ERROR_EA_ACCESS_DENIED) then
        result:= true
      else
        result:= false;
    end
  else
    begin
      result:= true;
      CloseHandle(ph);
    end;
end;

function TNetTimeIPC.CheckServerRunning: boolean;
begin
  if ShareMem = nil then
    result:= false
  else
    result:= CheckProcessExists(ShareMem^.S_ServerPID);
end;

function TNetTimeIPC.CheckClientRunning: boolean;
begin
  if ShareMem = nil then
    result:= false
  else
    result:= CheckProcessExists(ShareMem^.C_ClientPID);
end;

procedure SignalEventByName(const name: string);
var
  EventHandle: THandle;
begin
  EventHandle:= OpenEvent(EVENT_ALL_ACCESS, false, PChar(name));
  if EventHandle <> 0 then
    begin
      SetEvent(EventHandle);
      CloseHandle(EventHandle);
    end;
end;

procedure TNetTimeIPC.KillEverything;
begin
  // MTG: Following code disabled because I've removed the capability for the client to tell the server to die
  // The client now has to have sufficient system privileges to kill the Windows service.
   
//  if ShareMem <> nil then
//    begin
//      ShareMem^.G_ExitNowFlag:= true;
//      SignalEventByName(ClientEventName);
//      SignalEventByName(ServerEventName);
//    end;
  if Assigned(ExitNowCallback) then
    ExitNowCallback;
end;

constructor TNetTimeIPC.Create(const enb: TExitNowCallback);
begin
  inherited Create;
  ExitNowCallback:= enb;
  HaveKilled:= false;
  ShareMem:= nil;
end;

destructor TNetTimeIPC.Destroy;
begin
  FreeResources;
  inherited;
end;

{ TNetTimeIPCServer }

procedure TNetTimeIPCServer.ClientHello;
begin
  ClientEvent:= OpenEvent(EVENT_ALL_ACCESS, false, PChar(ClientEventName));
end;

procedure TNetTimeIPCServer.ClientGoodbye;
begin
  ClientEvent:= 0;
end;

function TNetTimeIPCServer.LargeAdjustWarn(const ServerTime, StationTime: TDateTime): boolean;
begin
  if (ClientEvent = 0) or (ShareMem = nil) or (not CheckClientRunning) then
    begin
      result:= true;
      exit;
    end;
  ShareMem^.S_ServerTime:= ServerTime;
  ShareMem^.S_StationTime:= StationTime;
  ShareMem^.C_LargeAdjReplyFlag:= false;
  ShareMem^.S_LargeAdjFlag:= true;
  SetEvent(ClientEvent);
  repeat
    Sleep(IPCSleepTime);
  until ShareMem^.C_LargeAdjReplyFlag;
  ShareMem^.C_LargeAdjReplyFlag:= false;
  result:= ShareMem^.C_LargeAdjReplyResult;
end;

procedure TNetTimeIPCServer.AdviseStatus;
begin
  if ShareMem = nil then
    exit;
  ShareMem^.S_Status:= GetServerStatusCallback;
  ShareMem^.S_AdviseStatusFlag:= true;
  if (ClientEvent <> 0) then
    SetEvent(ClientEvent);
end;

procedure TNetTimeIPCServer.InitResources;
begin
  inherited;
  ShareMem^.G_MagicCookie:= MagicCookie;
  ShareMem^.G_ProtocolVersion:= ProtocolVersion;
  ShareMem^.S_ServerPID:= GetCurrentProcessID;
  MyThread:= TNetTimeServerThread.Create(Self);
end;

procedure TNetTimeIPCServer.FreeResources;
begin
  if ShareMem <> nil then
    ShareMem^.S_ServerPID:= 0;
  if MyThread <> nil then
    begin
      MyThread.Terminate;
      SetEvent(MyThread.MyEvent);
      MyThread.WaitFor;
      MyThread.Free;
      MyThread:= nil;
    end;
  inherited;
end;

constructor TNetTimeIPCServer.Create(const gsb: TGetServerStatusCallback; const scb: TSetConfigCallback;
  const ssb: TSetServerCallback; const enb: TExitNowCallback; const unb: TUpdateNowCallback);
begin
  inherited Create(enb);
  MyThread:= nil;
  GetServerStatusCallback:= gsb;
  SetConfigCallback:= scb;
  SetServerCallback:= ssb;
  UpdateNowCallback:= unb;
end;

destructor TNetTimeIPCServer.Destroy;
begin
  FreeResources;
  inherited;
end;

procedure TNetTimeIPCServer.SetServer;
begin
  if ShareMem <> nil then
    SetServerCallback(ShareMem^.C_Server);
end;

procedure TNetTimeIPCServer.SetConfig;
begin
  if ShareMem <> nil then
    SetConfigCallback(ShareMem^.C_Config);
end;

{ TNetTimeServerThread }

constructor TNetTimeServerThread.Create(const Owner: TNetTimeIPCServer; const Suspended: boolean = false);

var
  sa: TSecurityAttributes;
  sd: TSecurityDescriptor;
  sp: PSecurityAttributes;

begin
  inherited Create(true);
  MyOwner:= Owner;
  if IsWindowsNT then
    begin
      InitializeSecurityDescriptor(@sd, SECURITY_DESCRIPTOR_REVISION);
      SetSecurityDescriptorDACL(@sd, true, nil, false);
      sa.nLength:= sizeof(sa);
      sa.lpSecurityDescriptor:= @sd;
      sa.bInheritHandle:= false;
      sp:= @sa;
    end
  else
    sp:= nil;
  MyEvent:= CreateEvent(sp, true, false, PChar(ServerEventName));
  if MyEvent = 0 then
    raise exception.Create('Could not create server event');
  if not Suspended then
    Resume;
end;

procedure TNetTimeServerThread.Execute;
begin
  repeat
    ResetEvent(MyEvent);
    WaitForSingleObject(MyEvent, INFINITE);
    if MyOwner.ShareMem <> nil then
      with MyOwner.ShareMem^ do
        begin
          if (C_StatusWantedSerial <> S_StatusProvidedSerial) then
            begin
              S_Status:= MyOwner.GetServerStatusCallback;
              S_StatusProvidedSerial:= C_StatusWantedSerial;
            end;
          if C_SetConfigFlag then
            begin
              MyOwner.SetConfig;
              C_SetConfigFlag:= false;
            end;
          if C_SetServerFlag then
            begin
              MyOwner.SetServer;
              C_SetServerFlag:= false;
            end;
          if C_ClientStatusChangeFlag then
            begin
              if C_ClientPID <> 0 then
                MyOwner.ClientHello
              else
                MyOwner.ClientGoodbye;
              C_ClientStatusChangeFlag:= false;
            end;
          if C_WantUpdateNowFlag then
            begin
              if Assigned(MyOwner.UpdateNowCallback) then
                { S_LastUpdateGood := } MyOwner.UpdateNowCallback;
              C_WantUpdateNowFlag:= false;
            end;
          { if G_ExitNowFlag then
            begin
            if not MyOwner.HaveKilled then
            begin
            MyOwner.HaveKilled := true;
            if Assigned(MyOwner.ExitNowCallback) then
            Synchronize(MyOwner.ExitNowCallback);
            end;
            end; }
        end;
  until Terminated;
end;

{ TNetTimeIPCClient }

function TNetTimeIPCClient.GetServerStatus: TServerStatusBlock;
var
  sws: Integer;
  crit: TCriticalSection;
begin
  if ShareMem = nil then
    raise exception.Create('Shared memory not mapped');
  if not CheckServerRunning then
    raise exception.Create('Server died');
  ShareMem^.S_AdviseStatusFlag:= false;
  crit:= TCriticalSection.Create;
  try
    crit.Acquire;
    sws:= ShareMem^.C_StatusWantedSerial + 1;
    ShareMem^.C_StatusWantedSerial:= sws;
    crit.Release;
  finally
    crit.Free;
  end;
  SetEvent(ServerEvent);
  repeat
    Sleep(IPCSleepTime);
  until ShareMem^.S_StatusProvidedSerial = ShareMem^.C_StatusWantedSerial;
  result:= ShareMem^.S_Status;
end;

procedure TNetTimeIPCClient.RetrieveStatus;
begin
  if ShareMem = nil then
    raise exception.Create('Shared memory not mapped');
  AdviseStatusCallback(ShareMem^.S_Status);
end;

procedure TNetTimeIPCClient.DoLargeAdj;
begin
  if ShareMem = nil then
    raise exception.Create('Shared memory not mapped');
  ShareMem^.C_LargeAdjReplyResult:= LargeAdjCallback(ShareMem^.S_ServerTime, ShareMem^.S_StationTime);
  ShareMem^.C_LargeAdjReplyFlag:= true;
end;

procedure TNetTimeIPCClient.SetConfig(const cfg: TServerConfigBlock);
begin
  if ShareMem = nil then
    raise exception.Create('Shared memory not mapped');
  if not CheckServerRunning then
    raise exception.Create('Server died');
  ShareMem^.C_Config:= cfg;
  ShareMem^.C_SetConfigFlag:= true;
  SetEvent(ServerEvent);
  repeat
    Sleep(IPCSleepTime);
  until ShareMem^.C_SetConfigFlag = false;
end;

procedure TNetTimeIPCClient.SetServer(const srv: boolean);
begin
  if ShareMem = nil then
    raise exception.Create('Shared memory not mapped');
  if not CheckServerRunning then
    raise exception.Create('Server died');
  ShareMem^.C_Server:= srv;
  ShareMem^.C_SetServerFlag:= true;
  SetEvent(ServerEvent);
  repeat
    Sleep(IPCSleepTime);
  until ShareMem^.C_SetServerFlag = false;
end;

procedure TNetTimeIPCClient.TriggerUpdateNow;
begin
  if ShareMem = nil then
    raise exception.Create('Shared memory not mapped');
  if not CheckServerRunning then
    raise exception.Create('Server died');
  ShareMem^.C_WantUpdateNowFlag:= true;
  SetEvent(ServerEvent);
end;

function TNetTimeIPCClient.UpdateNow: boolean;
begin
  TriggerUpdateNow;

  while ShareMem^.C_WantUpdateNowFlag or GetServerStatus.WantUpdate do
    begin
      Application.ProcessMessages;
      Sleep(IPCSleepTime);
    end;

  result:= GetServerStatus.Status.Synchronized;
  // result := ShareMem^.S_LastUpdateGood;
end;

procedure TNetTimeIPCClient.InitResources;
begin
  inherited;
  if (ShareMem^.G_MagicCookie <> MagicCookie) or (ShareMem^.G_ProtocolVersion <> ProtocolVersion) then
    raise exception.Create('Could not connect to server: Server is running a different version of NetTime.');
  ServerEvent:= OpenEvent(EVENT_ALL_ACCESS, false, PChar(ClientEventName));
  if ServerEvent = 0 then
    raise exception.Create('Could not open server event: error ' + inttostr(GetLastError));
  MyThread:= TNetTimeClientThread.Create(Self);
  ShareMem^.C_ClientPID:= GetCurrentProcessID;
  ShareMem^.C_ClientStatusChangeFlag:= true;
  SetEvent(ServerEvent);
end;

procedure TNetTimeIPCClient.FreeResources;
begin
  if ShareMem <> nil then
    begin
      ShareMem^.C_ClientPID:= 0;
      ShareMem^.C_ClientStatusChangeFlag:= true;
      if ServerEvent <> 0 then
        SetEvent(ServerEvent);
    end;
  if MyThread <> nil then
    begin
      MyThread.Terminate;
      SetEvent(MyThread.MyEvent);
      MyThread.WaitFor;
      MyThread.Free;
      MyThread:= nil;
    end;
  inherited;
end;

constructor TNetTimeIPCClient.Create(const asb: TAdviseStatusCallback; const lab: TLargeAdjCallback;
  const enb: TExitNowCallback);
begin
  inherited Create(enb);
  AdviseStatusCallback:= asb;
  LargeAdjCallback:= lab;
  ServerEvent:= 0;
  MyThread:= nil;
end;

destructor TNetTimeIPCClient.Destroy;
begin
  if ShareMem <> nil then
    begin
      ShareMem^.C_ClientPID:= 0;
      ShareMem^.C_ClientStatusChangeFlag:= true;
      SetEvent(ServerEvent);
    end;
  if ServerEvent <> 0 then
    CloseHandle(ServerEvent);
  MyThread.Terminate;
  if MyThread.MyEvent <> 0 then
    SetEvent(MyThread.MyEvent);
  inherited;
end;

{ TNetTimeClientThread }

constructor TNetTimeClientThread.Create(const Owner: TNetTimeIPCClient; const Suspended: boolean = false);

var
  {
    sa: TSecurityAttributes;
    sd: TSecurityDescriptor;
  }
  sp: PSecurityAttributes;

begin
  inherited Create(true);
  MyOwner:= Owner;
  // if IsWindowsNT then
  // begin
  // InitializeSecurityDescriptor(@sd,SECURITY_DESCRIPTOR_REVISION);
  // sa.nLength := sizeof(sa);
  // sa.lpSecurityDescriptor := @sd;
  // sa.bInheritHandle := false;
  // sp := @sa;
  // end
  // else
  sp:= nil;
  MyEvent:= CreateEvent(sp, true, false, PChar(ClientEventName));
  if MyEvent = 0 then
    raise exception.Create('Could not create client event');
  if not Suspended then
    Resume;
end;

procedure TNetTimeClientThread.Execute;
begin
  repeat
    ResetEvent(MyEvent);
    WaitForSingleObject(MyEvent, INFINITE);
    if MyOwner.ShareMem <> nil then
      with MyOwner.ShareMem^ do
        begin
          if S_AdviseStatusFlag then
            begin
              Synchronize(MyOwner.RetrieveStatus);
              S_AdviseStatusFlag:= false;
            end;
          if S_LargeAdjFlag then
            begin
              Synchronize(MyOwner.DoLargeAdj);
              S_LargeAdjFlag:= false;
            end;
          { if G_ExitNowFlag then
            begin
            if not MyOwner.HaveKilled then
            begin
            MyOwner.HaveKilled := true;
            if Assigned(MyOwner.ExitNowCallback) then
            Synchronize(MyOwner.ExitNowCallback);
            end;
            end; }
        end;
  until Terminated;
end;

end.
