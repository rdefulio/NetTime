{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit ntptime;

interface

uses classes, windows, messages, sysutils, timeconv, winsock, winsockutil,
  NetTimeCommon, Logging;

var
  NTP_ReferenceID: Cardinal = 0;

type

  TNTPRequest = record
    LI_VN_Mode: byte;
    Stratum: byte;
    Poll: byte;
    Precision: shortint;
    RootDelay: longword;
    RootDispersion: longword;
    ReferenceID: longword;
    ReferenceTimestamp: TNTPTimestamp;
    OriginateTimestamp: TNTPTimestamp;
    ReceiveTimestamp: TNTPTimestamp;
    TransmitTimestamp: TNTPTimestamp;
  end;

  TNTPServerThread = class(TQuickUDPServerThread)
  protected
    procedure DoRequest; override;
  end;

Function ClockSyncGood: Boolean;
procedure GetTimeFromNTP(const h: string; const port: integer; var status: TSyncServerStatus; var Time: TDateTime;
  var NetLag: TDateTime; var RetrievalTime: TDateTime);

procedure FindServersViaBroadcast(const ResultList: TStrings);

type
  TTimeSyncGoodFunc = function: boolean of object;
  TTimeLastUpdatedFunc = function: TDateTime of object;

var
  AlwaysProvideTime: Boolean;
  TimeSyncGoodFunc: TTimeSyncGoodFunc;
  TimeLastUpdatedFunc: TTimeLastUpdatedFunc;

implementation

Function ClockSyncGood: Boolean;
begin
  Result:= False;

  if AlwaysProvideTime then
    begin
      Result:= True;
      exit;
    end;

  if @TimeSyncGoodFunc = nil then
    exit;

  Result:= TimeSyncGoodFunc;
end;

procedure PackLI_VN_Mode(const LI, VN, Mode: byte; var LI_VN_Mode: byte);
begin
  LI_VN_Mode:= (LI * 64) + (VN * 8) + Mode;
end;

procedure UnpackLI_VN_Mode(const LI_VN_Mode: byte; var LI, VN, Mode: byte);
begin
  LI:= (LI_VN_Mode div 64) mod 4;
  VN:= (LI_VN_Mode div 8) mod 8;
  Mode:= LI_VN_Mode mod 8;
end;

// 2/5/2011 - MTG Changed "abort" calls to "exit" because the silent exception was bypassing code that should still be run!
procedure GetTimeFromNTP(const h: string; const port: integer; var status: TSyncServerStatus; var Time: TDateTime;
  var NetLag: TDateTime; var RetrievalTime: TDateTime);
var
  addr: longword;
  sock: TSocket;
  req: TNTPRequest;
  remote: sockaddr_in;
  T1, T2, T3, T4: TDateTime;
  arg: integer;
  ReferenceIDChars: Array[0..4] of AnsiChar;
begin
  status:= ssFailed;
  addr:= StrToAddr(h);
  if addr = longword(INADDR_NONE) then
    exit;
  sock:= Socket(AF_INET, SOCK_DGRAM, 0);
  if sock = INVALID_SOCKET then
    exit;
  try
    arg:= 10000; // 10 seconds
    if setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, @arg, sizeof(arg)) = SOCKET_ERROR then
      exit;

    T1:= Now;
    FillChar(req, sizeof(req), 0);
    PackLI_VN_Mode(0, 3, 3, req.LI_VN_Mode);
    req.TransmitTimestamp:= DateTimeToNTP(Now);
    remote.sin_family:= AF_INET;
    remote.sin_addr.s_addr:= addr;
    remote.sin_port:= htons(port);
    if sendto(sock, req, sizeof(req), 0, remote, sizeof(remote)) = SOCKET_ERROR then
      exit;
    arg:= sizeof(remote);
    if recvfrom(sock, req, sizeof(req), 0, remote, arg) <> sizeof(req) then
      exit;

    T2:= NTPToDateTime(req.ReceiveTimestamp);
    T3:= NTPToDateTime(req.TransmitTimestamp);
    T4:= Now;
    RetrievalTime:= T4;
    NetLag:= (T4 - T1) - (T2 - T3);
    Time:= T3 + NetLag / 2;

    if LogLevel >= log_Debug then
      begin
        LogMessage('NTP Response from: '+inet_ntoa(in_addr(remote.sin_addr)), log_Debug);
        LogMessage('NTP Response Stratum: '+IntToStr(req.Stratum), log_Debug);

        if req.Stratum <= 1 then
          begin
            FillChar(ReferenceIDChars, SizeOf(ReferenceIDChars), 0);
            Move(req.ReferenceID, ReferenceIDChars, 4);
            LogMessage('NTP Response Reference ID: '+StrPas(ReferenceIDChars), log_Debug);
          end
        else
          LogMessage('NTP Response Reference IP: '+inet_ntoa(in_addr(req.ReferenceID)), log_Debug);
      end;

    if req.Stratum = 0 then
      status:= ssKoD
    else
      begin
        if (req.TransmitTimestamp.Seconds = 0) then
          status:= ssFailed
        else
          status:= ssGood;
      end;
  finally
    CloseSocket(sock);
  end;
end;

procedure FindServersViaBroadcast(const ResultList: TStrings);

var
  sock: TSocket;
  req: TNTPRequest;
  remote: sockaddr_in;
  arg: integer;
  siz: integer;
  hostptr: PHostEnt;
  MyHostName: ShortString;

begin
  GetHostName(@(MyHostName[1]), sizeof(MyHostName) - 1);
  SetLength(MyHostName, pos(#0, MyHostName) - 1);
  sock:= Socket(AF_INET, SOCK_DGRAM, 0);
  if sock = INVALID_SOCKET then
    exit;
  arg:= 2000; // 2 seconds - if it takes longer than that, it's not local!
  if setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, @arg, sizeof(arg)) = SOCKET_ERROR then
    exit;
  arg:= 1;
  if setsockopt(sock, SOL_SOCKET, SO_BROADCAST, @arg, sizeof(arg)) = SOCKET_ERROR then
    exit;
  FillChar(req, sizeof(req), 0);
  PackLI_VN_Mode(0, 3, 3, req.LI_VN_Mode);
  req.TransmitTimestamp:= DateTimeToNTP(Now);
  remote.sin_family:= AF_INET;
  remote.sin_addr.s_addr:= integer(INADDR_BROADCAST);
  remote.sin_port:= htons(NTP_Port);
  if sendto(sock, req, sizeof(req), 0, remote, sizeof(remote)) = SOCKET_ERROR then
    exit;
  arg:= sizeof(remote);
  siz:= recvfrom(sock, req, sizeof(req), 0, remote, arg);
  while siz <> SOCKET_ERROR do
    begin
      if siz = sizeof(req) then
        begin
          hostptr:= GetHostByAddr(@remote.sin_addr, sizeof(remote.sin_addr), PF_INET);
          if hostptr = nil then
            ResultList.Add(inet_ntoa(remote.sin_addr))
          else
            if hostptr^.h_name <> MyHostName then
              ResultList.Add(hostptr^.h_name)
        end;
      arg:= sizeof(remote);
      siz:= recvfrom(sock, req, sizeof(req), 0, remote, arg);
    end;
end;

procedure TNTPServerThread.DoRequest;

var
  Request, Response: TNTPRequest;
  LI, VN, Mode: byte;

begin
  if Req_Len <> sizeof(TNTPRequest) then
    begin
      LogMessage('NTP Request received with invalid size: '+IntToStr(Req_Len), log_Debug);
      exit;
    end;
    
  Move(req, Request, sizeof(TNTPRequest));
  UnpackLI_VN_Mode(Request.LI_VN_Mode, LI, VN, Mode);

  // Changed on 4/5/2012 by MTG to allow the default Windows time client to sync to NetTime!
//  if (Mode <> 3) then
  if not (Mode in [1..3]) then
    begin
      LogMessage('NTP Request received with invalid mode: '+IntToStr(Mode), log_Debug);
      exit;
    end;
  if (VN > 4) then
    begin
      LogMessage('NTP Request received is invalid version number: '+IntToStr(VN), log_Debug);
      exit;
    end;
  FillChar(Response, sizeof(Response), 0);

  if ClockSyncGood then
    LI:= 0
  else
    LI:= 3;
  Mode:= 4;
  PackLI_VN_Mode(LI, VN, Mode, Response.LI_VN_Mode);
  Response.Stratum:= 14;  // changed from 15 to 14 by MTG on 4/5/2012 because the default Windows Time Client doesn't like a Stratum of 15!
  Response.Poll:= Request.Poll;
  Response.Precision:= -6;
  if ClockSyncGood then
    begin
      Response.ReferenceID:= NTP_ReferenceID;
      Response.ReferenceTimestamp:= DateTimeToNTP(TimeLastUpdatedFunc);
      Response.OriginateTimestamp:= Request.TransmitTimestamp;
      Response.ReceiveTimestamp:= DateTimeToNTP(Now);
      Response.TransmitTimestamp:= Response.ReceiveTimestamp;
    end;
  sendto(sock, Response, sizeof(Response), 0, remote, sizeof(remote));

  LogMessage('Sent NTP Response to: '+inet_ntoa(in_addr(Remote.sin_addr)), log_Verbose);
end;


initialization

TimeSyncGoodFunc:= nil;
TimeLastUpdatedFunc:= nil;

end.
