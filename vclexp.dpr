program vclexp;

uses
  Forms,
  Main in 'Main.pas' {Form1},
  Dump in 'Dump.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

