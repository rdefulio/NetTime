{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  ************************************************************************ }

unit warning;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, Buttons;

type
  TfrmWarning = class(TForm)
    Label1: TLabel;
    Label2: TLabel;
    lblServerTime: TLabel;
    Label4: TLabel;
    lblStationTime: TLabel;
    rbnUpdate: TRadioButton;
    rbnShutdown: TRadioButton;
    Label3: TLabel;
    Button1: TButton;
  private
    { Private declarations }
  public
    { Public declarations }
  end;

implementation

{$R *.DFM}

end.
