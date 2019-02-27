{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit unixtime;

interface

uses classes, winsock, winsockutil, NetTimeCommon, ntptime, Logging;

type
  TRFC868_UDPServerThread = class(TQuickUDPServerThread)
  private
    time: longword;
  protected
    procedure DoRequest; override;
  end;

  TRFC868_TCPServerThread = class(TThread)
  private
    sock: TSocket;
    connsock: TSocket;
    listener: sockaddr_in;
    remote: sockaddr_in;
    arg: integer;
    time: longword;
    listen_port: integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const Suspended: boolean; const Port: integer);
  end;

procedure GetTimeFromHost(const h: string; const Port: integer; const udp: boolean; var status: TSyncServerStatus;
  var time: TDateTime; var NetLag: TDateTime; var RetrievalTime: TDateTime);

implementation

uses Windows, SysUtils, Forms, timeconv, Dialogs;

procedure GetTimeFromHost(const h: string; const Port: integer; const udp: boolean; var status: TSyncServerStatus;
  var time: TDateTime; var NetLag: TDateTime; var RetrievalTime: TDateTime);
var
  net_begin, net_end: TDateTime;
  addr: longword;
  sock: TSocket;
  remote: sockaddr_in;
  arg: integer;
  rcvtime: longword;
begin
  status:= ssFailed;
  addr:= StrToAddr(h);
  if addr = longword(INADDR_NONE) then
    exit;
  if udp then
    sock:= Socket(AF_INET, SOCK_DGRAM, 0)
  else
    sock:= Socket(AF_INET, SOCK_STREAM, 0);
  if sock = INVALID_SOCKET then
    exit;
  try
    arg:= 10000; // 10 seconds
    if setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, @arg, sizeof(arg)) = SOCKET_ERROR then
      exit;
    remote.sin_family:= AF_INET;
    remote.sin_addr.s_addr:= addr;
    remote.sin_port:= htons(Port);
    net_begin:= now;
    if udp then
      begin
        arg:= 0;
        if sendto(sock, arg, sizeof(arg), 0, remote, sizeof(remote)) = SOCKET_ERROR then
          exit;
        arg:= sizeof(remote);
        if recv(sock, rcvtime, sizeof(rcvtime), 0) <> sizeof(rcvtime) then
          exit;
        status:= ssGood;
      end
    else
      begin
        if Connect(sock, remote, sizeof(remote)) = SOCKET_ERROR then
          exit;
        if recv(sock, rcvtime, sizeof(rcvtime), 0) <> sizeof(rcvtime) then
          exit;
        status:= ssGood;
      end;
    net_end:= now;
    RetrievalTime:= net_end;
    NetLag:= (net_end - net_begin);
    time:= rfc868timetodatetime(rcvtime) + (NetLag / 2);
  finally
    CloseSocket(sock);
  end;
end;

procedure TRFC868_UDPServerThread.DoRequest;
begin
  if not ntptime.ClockSyncGood then
    exit;

  time:= DateTimeToRFC868Time(now);
  sendto(sock, time, sizeof(time), 0, remote, sizeof(remote));

  LogMessage('Sent RFC868 (UDP) Response to: '+inet_ntoa(in_addr(Remote.sin_addr)), log_Verbose);
end;

constructor TRFC868_TCPServerThread.Create(const Suspended: boolean; const Port: integer);
begin
  inherited Create(true);
  listen_port:= Port;
  if not Suspended then
    Resume;
end;

procedure TRFC868_TCPServerThread.Execute;
begin
  FreeOnTerminate:= true;
  sock:= Socket(AF_INET, SOCK_STREAM, 0);
  if sock = INVALID_SOCKET then
    raise exception.Create('Could not allocate socket: Winsock error ' + inttostr(WSAGetLastError));
  arg:= 10000; // 10 seconds
  if setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, @arg, sizeof(arg)) = SOCKET_ERROR then
    raise exception.Create('Error setting socket timeout: Winsock error ' + inttostr(WSAGetLastError));
  fillchar(listener, sizeof(listener), 0);
  listener.sin_family:= AF_INET;
  listener.sin_addr.s_addr:= INADDR_ANY;
  listener.sin_port:= htons(listen_port);
  if bind(sock, listener, sizeof(sockaddr_in)) = SOCKET_ERROR then
    raise exception.Create('Cannot bind to port: Winsock error ' + inttostr(WSAGetLastError));
  if listen(sock, SOMAXCONN) = SOCKET_ERROR then
    raise exception.Create('Failure to listen: Winsock error ' + inttostr(WSAGetLastError));
  while not Terminated do
    begin
      arg:= sizeof(sockaddr_in);
      connsock:= accept(sock, @remote, @arg);
      if connsock <> INVALID_SOCKET then
        begin
          if ntptime.ClockSyncGood then
            begin
              time:= DateTimeToRFC868Time(now);
              send(connsock, time, sizeof(time), 0);
              LogMessage('Sent RFC868 (TCP) Response to: '+inet_ntoa(in_addr(Remote.sin_addr)), log_Verbose);
            end;
          CloseSocket(connsock);
        end;
    end;
  CloseSocket(sock);
end;

end.
