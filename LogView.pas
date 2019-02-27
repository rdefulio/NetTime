unit LogView;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Logging, ExtCtrls;

type
  TLogViewForm = class(TForm)
    Log: TMemo;
    Close: TButton;
    Timer1: TTimer;
    procedure CloseClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    Procedure ShowForm;
  end;

var
  LogViewForm: TLogViewForm;

implementation

{$R *.dfm}

procedure TLogViewForm.CloseClick(Sender: TObject);
begin
  Hide;
end;

Procedure TLogViewForm.ShowForm;
begin
  LoggingCriticalSection.Enter;
  try
    try
      Log.Lines.LoadFromFile(LogFileName);
    except
      on Exception do
        begin
          Application.MessageBox('Error Loading Log File - may be missing!', 'Error', 0);
          exit;
        end;
    end;
    LoggingNewLines:= '';
  finally
    LoggingCriticalSection.Leave;
  end;

  Log.SelStart:= MaxLongInt;

  if Log.Lines.Count > 0 then
    Show
  else
    Application.MessageBox('Log is empty!', 'Error', 0);

  SendMessage(Log.Handle, EM_SCROLLCARET, 0, 0);
end;

procedure TLogViewForm.Timer1Timer(Sender: TObject);
begin
  LoggingCriticalSection.Enter;
  try
    if LoggingNewLines <> '' then
      begin
        Log.Lines.Add(LoggingNewLines);
        LoggingNewLines:= '';
      end;
  finally
    LoggingCriticalSection.Leave;
  end;
end;

end.
