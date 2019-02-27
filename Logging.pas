{ ************************************************************************

  This file is copyrighted 2011 by Mark Griffiths. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed.

  ************************************************************************ }

unit Logging;

interface

uses SysUtils, SyncObjs, Windows;

const
  log_None = 0;
  log_Normal = 1;
  log_Verbose = 2;
  log_Debug = 3;

  DefaultLogLevel = log_Normal;

  crlf = #13#10;

var
  LogLevel: Integer;
  LogFileName: string;
  LoggingCriticalSection: TCriticalSection;

  LoggingNewLines: String;

Function LogLevelToStr(LogLevel: Integer): String;
procedure LogMessage(Msg: string; Level: Integer = log_Normal; IncludeTimestamp: Boolean = True);

implementation

Function LogLevelToStr(LogLevel: Integer): String;
begin
  case LogLevel of
    log_None:       Result:= 'None';
    log_Normal:     Result:= 'Normal';
    log_Verbose:    Result:= 'Verbose';
    log_Debug:      Result:= 'Debug';
  else
    Result:= 'Unknown';
  end;
end;

procedure LogMessage(Msg: string; Level: Integer = log_Normal; IncludeTimestamp: Boolean = True);
var
  f: TextFile;
begin
  if LogFileName = '' then
    exit;

  if Level <= LogLevel then
    begin
      AssignFile(f, LogFileName);

      LoggingCriticalSection.Enter;
      try
        try
          try
            if FileExists(LogFileName) then
              Append(f)
            else
              Rewrite(f);

            if IncludeTimestamp then
              Msg:= DateTimeToStr(Now) + ' ' + Msg;

            Writeln(f, Msg);

            if LoggingNewLines <> '' then
              LoggingNewLines:= LoggingNewLines + #13#10 + Msg
            else
              LoggingNewLines:= Msg;
          except;
            MessageBox(0, 'Exception whilst writing log msg', 'Debug', 0);
          end;
        finally
          CloseFile(f);
        end;
      finally
        LoggingCriticalSection.Leave;
      end;
    end;
end;

initialization

LoggingCriticalSection:= TCriticalSection.Create;

finalization

LoggingCriticalSection.Free;

end.
