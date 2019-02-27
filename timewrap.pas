{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011 - Mark Griffiths

  ************************************************************************ }

unit timewrap;

interface

uses Windows, Forms, Classes, SysUtils, NetTimeCommon, WinSockUtil, Winsock, Logging, timeconv;

procedure GetTimeFromServer(const ServerDef: TServerDef; var ServerData: TServerData; UsedIPAddresses: TStrings = nil);

procedure GetTimeFromServerAsync(const ServerDef: TServerDef; var ServerData: TServerData);

procedure FigureBestKnownTime(const ServerCount: integer; var Servers: TServerDefArray; var Status: TSyncStatus;
  var Time: TDateTime; DemoteOnErrorCount: integer);

implementation

uses unixtime, ntptime;

procedure GetTimeFromServer(const ServerDef: TServerDef; var ServerData: TServerData; UsedIPAddresses: TStrings = nil);
var
  NewIPAddress: LongWord;
  IPAddressStr: string;
  Status: TSyncServerStatus;
  Msg: string;
begin
  Status:= ssFailed;

  try
    ServerData.HostName:= ServerDef.HostName;
    NewIPAddress:= StrToAddr(ServerDef.HostName);
    IPAddressStr:= inet_ntoa(in_addr(NewIPAddress));

    if NewIPAddress = LongWord(INADDR_NONE) then
      begin
        // LogMessage(ServerDef.HostName + ': Unable to resolve!', log_Debug);
        Status:= ssNoIP;
        exit;
      end;

    if (NewIPAddress <> LongWord(INADDR_NONE)) and (NewIPAddress <> ServerData.IPAddress) then
      begin
        ServerData.IPAddress:= NewIPAddress;
        LogMessage(ServerDef.HostName + ' resolved to ' + IPAddressStr, log_Verbose);
      end;

    if Assigned(UsedIPAddresses) then
      begin
        if (UsedIPAddresses.IndexOf(IPAddressStr) >= 0) then
          begin
            Status:= ssDuplicateIP;
            exit;
          end;

        UsedIPAddresses.Add(IPAddressStr);
      end;

    case ServerDef.protocol of
      ttpRFC868_UDP:
        GetTimeFromHost(IPAddressStr, ServerDef.port, True, Status, ServerData.Time, ServerData.Netlag,
          ServerData.RetrievalTime);
      ttpRFC868_TCP:
        GetTimeFromHost(IPAddressStr, ServerDef.port, False, Status, ServerData.Time, ServerData.Netlag,
          ServerData.RetrievalTime);
      ttpNTP:
        GetTimeFromNTP(IPAddressStr, ServerDef.port, Status, ServerData.Time, ServerData.Netlag,
          ServerData.RetrievalTime);
    else
      Status:= ssUnconfigured;
    end;

    if Status = ssGood then
      begin
        ServerData.RetrievalTime:= Now;
        ServerData.Offset:= Round((ServerData.Time - ServerData.RetrievalTime) * 86400 * 1000);
        ServerData.TimeLag:= Round(ServerData.Netlag * 86400 * 1000);
      end;
  finally
    SetSyncServerStatus(ServerData, Status);

    if Status = ssKoD then
      LogMessage('Kiss of Death received from: ' + ServerDef.HostName);

    if LogLevel >= log_Verbose then
      begin
        Msg:= ServerDef.HostName + ': ' + SyncServerStatusToStr(ServerData.Status);

        if ServerData.Status = ssGood then
          Msg:= Msg + ' ' + GetOffSetStr(ServerData.Offset) + ' (' + IntToStr(ServerData.TimeLag) + 'ms)';

        LogMessage(Msg, log_Verbose);
      end;
  end;
end;

type
  PBoolean = ^boolean;
  PStatus = ^TSyncServerStatus;
  PDateTime = ^TDateTime;

  TRetrieverThread = class(TThread)
  protected
    FServerDef: TServerDef;
    FServerData: PServerData;
    procedure Execute; override;
  public
    constructor Create(const ServerDef: TServerDef; var ServerData: TServerData);
  end;

constructor TRetrieverThread.Create(const ServerDef: TServerDef; var ServerData: TServerData);
begin
  inherited Create(True);
  FreeOnTerminate:= True;
  FServerDef:= ServerDef;
  FServerData:= @ServerData;
  FServerData.Done:= False;
  Resume;
end;

procedure TRetrieverThread.Execute;
begin
  try
    try
      FServerData.Status:= ssFailed; // Don't use SetSyncServerStatus here

      GetTimeFromServer(FServerDef, FServerData^);
    except
      FServerData.Status:= ssFailed;
    end;
  finally
    FServerData.Done:= True;
  end;
end;

procedure GetTimeFromServerAsync(const ServerDef: TServerDef; var ServerData: TServerData);
begin
  TRetrieverThread.Create(ServerDef, ServerData);
end;

procedure FigureBestKnownTime(const ServerCount: integer; var Servers: TServerDefArray; var Status: TSyncStatus;
  var Time: TDateTime; DemoteOnErrorCount: integer);
var
  i: integer;
  GotCount: integer;
  CalcData: array [0 .. MaxServers] of TServerData; // Allow for an extra one to represent the local time!
  ServerIndex: integer;
  GotTime: boolean;
  Difference: Int64;
  UsedIPAddresses: TStrings;
  ServerOK: Boolean;

  procedure MarkAsWrong(var ServerData: TServerData);
  var
    i: integer;
  begin
    ServerData.Status:= ssWrong;

    for i:= 0 to ServerCount do
      if Status.ServerDataArray[i].HostName = ServerData.HostName then
        begin
          SetSyncServerStatus(Status.ServerDataArray[i], ssWrong);
          LogMessage('Rejected: ' + Status.ServerDataArray[i].HostName, log_Debug);
          exit;
        end;
  end;

  procedure DemoteServer(ServerIndex: integer);
  var
    ServerDef: TServerDef;
    ServerData: TServerData;
    NewServerIndex: integer;
    ErrorTimeOut: integer;
    i: integer;
  begin
    ErrorTimeOut:= Status.ServerDataArray[ServerIndex].ErrorTimeOut;
    NewServerIndex:= ServerIndex;

    while (NewServerIndex < ServerCount - 1) and
      (Status.ServerDataArray[NewServerIndex + 1].ErrorTimeOut < ErrorTimeOut) do
      Inc(NewServerIndex);

    if NewServerIndex <> ServerIndex then
      begin
        LogMessage('Demoting Server: ' + Servers[ServerIndex].HostName);
        ServerDef:= Servers[ServerIndex];
        ServerData:= Status.ServerDataArray[ServerIndex];

        for i:= ServerIndex to NewServerIndex - 1 do
          begin
            Servers[i]:= Servers[i + 1];
            Status.ServerDataArray[i]:= Status.ServerDataArray[i + 1];
          end;

        Servers[NewServerIndex]:= ServerDef;
        Status.ServerDataArray[NewServerIndex]:= ServerData;
      end;
  end;

begin
  for i:= 0 to ServerCount - 1 do
    SetSyncServerStatus(Status.ServerDataArray[i], ssNotUsed);

  for i:= ServerCount to MaxServers - 1 do
    SetSyncServerStatus(Status.ServerDataArray[i], ssUnconfigured);

  if not HaveLocalAddress then
    begin
      SetLastSyncError(Status, lse_NetworkDown);
      Time:= Now;
      exit;
    end;

  ServerIndex:= 0;
  GotTime:= False;

  with CalcData[0] do
    begin
      HostName:= 'localhost';
      IPAddress:= 0;
      Time:= Now;
      Netlag:= 0;
      Offset:= 0;
      RetrievalTime:= Time;
      Status:= ssGood;
      Done:= True;
    end;

  GotCount:= 1;

  // Keep getting times from servers until we get responses from 2 servers that agree within 1 second of each other
  // We include the local time, so if we get a response from a single server that is within 1 second of local time, we'll use the time from that single server!

  UsedIPAddresses:= TStringList.Create;

  while (not GotTime) and (ServerIndex < ServerCount) do
    begin
      if Status.ServerDataArray[ServerIndex].ErrorTimeOut <= 0 then
        begin
          GetTimeFromServer(Servers[ServerIndex], Status.ServerDataArray[ServerIndex], UsedIPAddresses);

          if Status.ServerDataArray[ServerIndex].Status = ssGood then
            begin
              CalcData[GotCount]:= Status.ServerDataArray[ServerIndex];
              Inc(GotCount);

              SortServerData(@CalcData, GotCount, sdsByOffset);

              // Go through the responses and find the 2 responses that are closest together!
              for i:= 1 to GotCount - 1 do
                begin
                  Difference:= Abs(CalcData[i].Offset - CalcData[i - 1].Offset);
                  if Difference < MaxDifferenceBetweenServers then  // Definitely got a valid time here.
                    GotTime:= True
                  else
                    begin
                      if Difference < MaxDifferenceFromLocalTime then
                        begin
                          // If it's within 10 seconds of the local time, that's good enough!
                          if (CalcData[i].HostName = 'localhost') or (CalcData[i-1].HostName = 'localhost') then
                            begin
                              GotTime:= True;
                            end;
                        end;
                    end;
                end;
            end;
        end;

      Inc(ServerIndex);
    end;
  UsedIPAddresses.Free;

  // If no good times, overall result is false
  // We'll always have at least one time because we're including local system time.
  if GotCount = 1 then
    begin
      SetLastSyncError(Status, lse_AllFailed);
      exit;
    end;

  if ServerCount = 1 then
    GotTime:= True; // If we only have one server, we'll have to take it's word for it!

  if not GotTime then
    begin
      SetLastSyncError(Status, lse_InconsistentResponses);
      exit;
    end;

  if ServerCount > 1 then
    begin
      // Go through and mark any servers that disagree by more than a second as wrong - work from either end
      // This assumes that there aren't 2 groups of servers which agree within themselves, but disagree between the groups - this should never happen!

      // Start from the bottom:
      i:= 0;
      while i <= GotCount - 2 do
        begin
          Difference:= CalcData[i + 1].Offset - CalcData[i].Offset;

          ServerOK:= Difference <= MaxDifferenceBetweenServers;

          if not ServerOK then
            begin
              // Allow a larger difference if it's being compared to the local time.
              ServerOK:= (Difference <= MaxDifferenceFromLocalTime) and ((CalcData[i+1].HostName = 'localhost') or (CalcData[i].HostName = 'localhost'))
            end;

          if not ServerOK then
            MarkAsWrong(CalcData[i])
          else
            Break;

          Inc(i);
        end;

      // Start from the top:
      i:= GotCount - 1;
      while i >= 1 do
        begin
          Difference:= CalcData[i].Offset - CalcData[i - 1].Offset;

          ServerOK:= Difference <= MaxDifferenceBetweenServers;

          if not ServerOK then
            begin
              // Allow a larger difference if it's being compared to the local time.
              ServerOK:= (Difference <= MaxDifferenceFromLocalTime) and ((CalcData[i-1].HostName = 'localhost') or (CalcData[i].HostName = 'localhost'))
            end;

          if not ServerOK then
            MarkAsWrong(CalcData[i])
          else
            Break;

          Dec(i);
        end;
    end;

  NTP_ReferenceID:= CalcData[0].IPAddress;

  Status.Offset:= GetAverageOffset(@CalcData, GotCount);
  Time:= Now + (Status.Offset / MillisecondsPerDay);

  Status.Synchronized:= True;

  for i:= ServerCount - 1 downto 0 do
    begin
      if ((DemoteOnErrorCount > 0) and (Status.ServerDataArray[i].Status in ssError) and
        (Status.ServerDataArray[i].ErrorCount >= DemoteOnErrorCount)) or (Status.ServerDataArray[i].Status = ssKoD) then
        DemoteServer(i);
    end;
end;

{
  // The following procedure fetches the time from ALL servers and then works out the best time from that.
  // New procedure to only query a single server (most of the time) implemented on 2/5/2011 by MTG

  procedure FigureBestKnownTime(const ServerCount: integer; const Servers: TServerDefArray; var Status: TSyncStatus; var Time: TDateTime; MinGoodServers: Integer; MaxDiscrepancy: Integer);
  var i: Integer;
  GotCount: Integer;
  CalcData: array[0..MaxServers-1] of TServerData;
  AllDone: Boolean;
  Difference: Int64;
  begin
  for i:= ServerCount to MaxServers-1 do
  Status.ServerDataArray[i].Status:= ssUnconfigured;

  if not HaveLocalAddress then
  begin
  SetLastSyncError(Status, lse_NetworkDown);
  for i:= 0 to ServerCount - 1 do
  Status.ServerDataArray[i].Status:= ssFailed;
  Time:= Now;
  exit;
  end;

  for i:= 0 to ServerCount-1 do
  GetTimeFromServerAsync(Servers[i], Status.ServerDataArray[i]);

  repeat
  Sleep(GUISleepTime);
  AllDone:= True;
  for i:= 0 to ServerCount - 1 do
  if not Status.ServerDataArray[i].Done then
  begin
  AllDone:= False;
  Break;
  end;
  until AllDone;

  // Extract only those times that were good
  GotCount:= 0;
  for i:= 0 to ServerCount-1 do
  if (Status.ServerDataArray[i].Status = ssGood) then
  begin
  CalcData[GotCount]:= Status.ServerDataArray[i];
  Inc(GotCount);
  end;

  // If no good times, overall result is false
  if GotCount = 0 then
  begin
  SetLastSyncError(Status, lse_AllFailed);
  exit;
  end;

  //TODO: find a better strategy here.
  NormalizeTimes(@CalcData, GotCount);
  SortServerData(@CalcData, GotCount, sdsByTime, True);

  if ServerCount < MinGoodServers then
  MinGoodServers:= ServerCount;

  if GotCount < MinGoodServers then
  begin
  SetLastSyncError(Status, lse_InsufficientResponses);
  exit;
  end;

  // Reject this sync if the times disagree by too much!

  Difference:= Round((CalcData[GotCount - 1].Time - CalcData[0].Time) * 86400 * 1000);  //  Difference in Milliseconds!

  if Difference > MaxDiscrepancy then
  begin
  SetLastSyncError(Status, lse_InconsistentResponses);
  exit;
  end;

  //  Time := CalcData[GotCount div 2].Time;
  Time:= GetAverageTime(@CalcData, GotCount);

  Status.Offset:= Round((Time - Now) * 86400 * 1000);

  Status.Synchronized:= True;
  end;
}
end.
