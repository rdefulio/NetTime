unit cwinsvc;

interface

Type DWord = Integer;

function ServiceGetStrCode(nID : integer) : string;
function ServiceGetStatus(sMachine, sService : string) : DWord;
function ServiceRunning(sMachine, sService : string) : boolean;
function ServiceStopped(sMachine, sService : string) : boolean;
function ServiceStart(sMachine, sService : string) : boolean;
function ServiceEnableAndStart(sMachine, sService: string): boolean;
function ServiceStop(sMachine, sService : string) : boolean;
function ServiceStopAndDisable(sMachine, sService: string; NewStartType: DWord): boolean;
function ServiceNotify(sMachine, sService: string; Code: Integer): boolean;

implementation

uses Windows, SysUtils, WinSvc, WinUtils;

// convert status codes returned by
// ServiceGetStatus() to string values
 
function ServiceGetStrCode(nID : integer) : string;
var
  s : string;
begin
  case nID of
   SERVICE_STOPPED          : s := 'STOPPED';
   SERVICE_RUNNING          : s := 'RUNNING';
   SERVICE_PAUSED           : s := 'PAUSED';
   SERVICE_START_PENDING    : s := 'START/PENDING';
   SERVICE_STOP_PENDING     : s := 'STOP/PENDING';
   SERVICE_CONTINUE_PENDING : s := 'CONTINUE/PENDING';
   SERVICE_PAUSE_PENDING    : s := 'PAUSE/PENDING';
  else
   s := 'UNKNOWN'; 
  end;
  Result := s;
end;


// return status code if successful, -1 if not
// return codes:
//   SERVICE_STOPPED
//   SERVICE_RUNNING
//   SERVICE_PAUSED
 
// following return codes are used to indicate that the // service is in the middle of getting to one
// of the above states:
//   SERVICE_START_PENDING
//   SERVICE_STOP_PENDING
//   SERVICE_CONTINUE_PENDING
//   SERVICE_PAUSE_PENDING
 
// sMachine:
//   machine name, ie: \\SERVER
//   empty = local machine
 
// sService
//   service name, ie: Alerter
 
function ServiceGetStatus(sMachine,
                          sService : string) : DWord;
var
 schm   : SC_Handle; //service control manager handle
 schs   : SC_Handle;      // service handle
 ss     : TServiceStatus; // service status
 dwStat : DWord;          // current service status
begin
  dwStat := -1;
  // connect to the service control manager
  schm := OpenSCManager( PChar(sMachine), Nil,
                         SC_MANAGER_CONNECT);
  // if successful...
  if(schm > 0)then
  begin
    // open a handle to the specified service
    // we want to query service status
    schs := OpenService( schm, PChar(sService),
                         SERVICE_QUERY_STATUS);
    // if successful...
    if(schs > 0)then
    begin
      // retrieve the current status
      //of the specified service   
      if (QueryServiceStatus( schs, ss)) then
      begin
        dwStat := ss.dwCurrentState;
      end;
      // close service handle
      CloseServiceHandle(schs);
    end;
    // close service control manager handle
    CloseServiceHandle(schm);
  end;
  Result := dwStat;
end;


// Return TRUE if the specified service is running,
// defined by the status code SERVICE_RUNNING. Return
// FALSE if the service is in any other state,
// including any pending states
 
function ServiceRunning(sMachine,
                        sService : string) : boolean;
begin
  Result := SERVICE_RUNNING =
            ServiceGetStatus(sMachine, sService);
end;


// Return TRUE if the specified service was stopped,
// defined by the status code SERVICE_STOPPED.

function ServiceStopped(sMachine,
                        sService : string) : boolean;
begin
  Result := SERVICE_STOPPED =
            ServiceGetStatus(sMachine, sService);
end;


// Return TRUE if successful
function ServiceStart(sMachine,
                      sService : string) : boolean;
var
  schm,
  schs   : SC_Handle;
  ss     : TServiceStatus;
  psTemp : PChar;
  dwChkP : DWord; // check point
begin
  ss.dwCurrentState:= 0;
  // connect to the service control manager
  schm := OpenSCManager(PChar(sMachine), nil,
                        SC_MANAGER_CONNECT);
  // if successful...
  if(schm > 0)then
  begin
    // open a handle to the specified service
    // we want to start the service and query service
    // status
    schs := OpenService(schm, PChar(sService),
            SERVICE_START or SERVICE_QUERY_STATUS);
    // if successful...
    if(schs > 0)then
    begin
      psTemp := Nil;
      if(StartService( schs, 0,psTemp))then
      begin
        // check status
        if(QueryServiceStatus(schs, ss))then
        begin
          while(SERVICE_RUNNING <> ss.dwCurrentState)do
          begin
            // dwCheckPoint contains a value that the
            // service increments periodically to
            // report its progress during a
            // lengthy operation. Save current value
            dwChkP := ss.dwCheckPoint;
            // wait a bit before checking status again
            // dwWaitHint is the estimated amount of
            // time the calling program should wait
            // before calling QueryServiceStatus()
            // again. Idle events should be
            // handled here...
//            MySleep(ss.dwWaitHint);
            MySleep(250);
            if not QueryServiceStatus(schs, ss) then
            begin
              // couldn't check status break from the
              // loop
              break;
            end;

            if ss.dwCheckPoint < dwChkP then
            begin
              // QueryServiceStatus didn't increment
              // dwCheckPoint as it should have.
              // Avoid an infinite loop by breaking
              break;
            end;
          end;
        end;
      end;
      // close service handle
      CloseServiceHandle(schs);
    end;
    // close service control manager handle
    CloseServiceHandle(schm);
  end;
  // Return TRUE if the service status is running
  Result := SERVICE_RUNNING = ss.dwCurrentState;
end;

// Return TRUE if successful
function ServiceEnableAndStart(sMachine, sService: string): boolean;
var schm,
    schs   : SC_Handle;
    ss     : TServiceStatus;
    psTemp : PChar;
    dwChkP : DWord; // check point
begin
  ss.dwCurrentState:= 0;
  // connect to the service control manager
  schm := OpenSCManager(PChar(sMachine), nil, SC_MANAGER_CONNECT);

  // if successful...
  if(schm > 0)then
  begin
    // open a handle to the specified service
    // we want to start the service and query service
    // status
    schs := OpenService(schm, PChar(sService), SERVICE_START or SERVICE_QUERY_STATUS or SERVICE_CHANGE_CONFIG);
    // if successful...
    if(schs > 0)then
    begin
      ChangeServiceConfig(schs, SERVICE_NO_CHANGE, SERVICE_AUTO_START, SERVICE_NO_CHANGE, nil, nil, nil, nil, nil, nil, nil);

      psTemp:= Nil;
      if StartService(schs, 0,psTemp) then
      begin
        // check status
        if(QueryServiceStatus(schs, ss))then
        begin
          while(SERVICE_RUNNING <> ss.dwCurrentState)do
          begin
            // dwCheckPoint contains a value that the
            // service increments periodically to
            // report its progress during a
            // lengthy operation. Save current value
            dwChkP := ss.dwCheckPoint;
            // wait a bit before checking status again
            // dwWaitHint is the estimated amount of
            // time the calling program should wait
            // before calling QueryServiceStatus()
            // again. Idle events should be
            // handled here...
//            MySleep(ss.dwWaitHint);
            MySleep(250);
            if not QueryServiceStatus(schs, ss) then
            begin
              // couldn't check status break from the
              // loop
              break;
            end;

            if ss.dwCheckPoint < dwChkP then
            begin
              // QueryServiceStatus didn't increment
              // dwCheckPoint as it should have.
              // Avoid an infinite loop by breaking
              break;
            end;
          end;
        end;
      end;
      // close service handle
      CloseServiceHandle(schs);
    end;
    // close service control manager handle
    CloseServiceHandle(schm);
  end;
  // Return TRUE if the service status is running
  Result := SERVICE_RUNNING = ss.dwCurrentState;
end;

// Return TRUE if successful
function ServiceStop(sMachine,
                     sService : string) : boolean;
var
  schm,
  schs   : SC_Handle;
  ss     : TServiceStatus;
  dwChkP : DWord;
begin
  // connect to the service control manager
  schm := OpenSCManager(PChar(sMachine), nil,
                        SC_MANAGER_CONNECT);
  // if successful...
  if schm > 0 then
  begin
    // open a handle to the specified service
    // we want to stop the service and
    // query service status
    schs := OpenService( schm, PChar(sService),
            SERVICE_STOP or SERVICE_QUERY_STATUS);
    // if successful...
    if schs > 0 then
    begin
      if ControlService(schs, SERVICE_CONTROL_STOP,
                        ss) then
      begin
        // check status
        if(QueryServiceStatus(schs, ss))then
        begin
          while(SERVICE_STOPPED <> ss.dwCurrentState)do
          begin
            // dwCheckPoint contains a value that the
            // service increments periodically to
            // report its progress during a lengthy
            // operation. Save current value
            dwChkP := ss.dwCheckPoint;
            // Wait a bit before checking status again.
            // dwWaitHint is the estimated amount of
            // time the calling program should wait
            // before calling QueryServiceStatus()
            // again. Idle events should be
            // handled here...
//            MySleep(ss.dwWaitHint);
            MySleep(250);

            if(not QueryServiceStatus(schs,ss))then
            begin
              // couldn't check status
              // break from the loop
              break;
            end;

            if(ss.dwCheckPoint <
              dwChkP)then
            begin
              // QueryServiceStatus didn't increment
              // dwCheckPoint as it should have.
              // Avoid an infinite loop by breaking
              break;
            end;
          end;
        end;
      end;

      // close service handle
      CloseServiceHandle(schs);
    end;

    // close service control manager handle
    CloseServiceHandle(schm);
  end;

  // return TRUE if the service status is stopped
  Result := SERVICE_STOPPED = ss.dwCurrentState;
end;

// Return TRUE if successful
function ServiceStopAndDisable(sMachine, sService: string; NewStartType: DWord): boolean;
var
  schm,
  schs   : SC_Handle;
  ss     : TServiceStatus;
  dwChkP : DWord;
begin
  // connect to the service control manager
  schm := OpenSCManager(PChar(sMachine), nil,
                        SC_MANAGER_CONNECT);
  // if successful...
  if schm > 0 then
  begin
    // open a handle to the specified service
    // we want to stop the service and
    // query service status
    schs := OpenService( schm, PChar(sService), SERVICE_STOP or SERVICE_QUERY_STATUS or SERVICE_CHANGE_CONFIG);
    // if successful...
    if schs > 0 then
    begin
      if ControlService(schs, SERVICE_CONTROL_STOP,
                        ss) then
      begin
        // check status
        if(QueryServiceStatus(schs, ss))then
        begin
          while(SERVICE_STOPPED <> ss.dwCurrentState)do
          begin
            // dwCheckPoint contains a value that the
            // service increments periodically to
            // report its progress during a lengthy
            // operation. Save current value
            dwChkP := ss.dwCheckPoint;
            // Wait a bit before checking status again.
            // dwWaitHint is the estimated amount of
            // time the calling program should wait
            // before calling QueryServiceStatus()
            // again. Idle events should be
            // handled here...
//            MySleep(ss.dwWaitHint);
            MySleep(250);

            if(not QueryServiceStatus(schs,ss))then
            begin
              // couldn't check status
              // break from the loop
              break;
            end;

            if(ss.dwCheckPoint <
              dwChkP)then
            begin
              // QueryServiceStatus didn't increment
              // dwCheckPoint as it should have.
              // Avoid an infinite loop by breaking
              break;
            end;
          end;
          ChangeServiceConfig(schs, SERVICE_NO_CHANGE, NewStartType, SERVICE_NO_CHANGE, nil, nil, nil, nil, nil, nil, nil);
        end;
      end;

      // close service handle
      CloseServiceHandle(schs);
    end;

    // close service control manager handle
    CloseServiceHandle(schm);
  end;

  // return TRUE if the service status is stopped
  Result := SERVICE_STOPPED = ss.dwCurrentState;
end;

function ServiceNotify(sMachine, sService: string; Code: Integer): boolean;
var schm,
    schs   : SC_Handle;
    ss     : TServiceStatus;
begin
  Result:= False;
  schm:= OpenSCManager(PChar(sMachine), nil, SC_MANAGER_CONNECT);
  if schm > 0 then
    begin
      schs:= OpenService( schm, PChar(sService), SERVICE_ALL_ACCESS);
      if schs > 0 then
        begin
          Result:= ControlService(schs, Code, ss);

          CloseServiceHandle(schs);
        end;
      CloseServiceHandle(schm);
    end;
end;


end.