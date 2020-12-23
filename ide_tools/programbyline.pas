unit ProgramByLine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, process, UTF8Process, Pipes, strutils, LConvEncoding
  {$IFDEF WINDOWS},Windows{$ENDIF};

type
  IProgramByLine = interface;
  TProgramByLineEvent = procedure(const Sender: IProgramByLine; const ALine: string;
      const AIsAddToLastLine: Boolean) of object;

  { IProgramByLine }

  IProgramByLine = interface
    ['{F0C02B9C-F6D8-4AFA-8854-1F9F64806B0E}']
    function GetOnLine: TProgramByLineEvent;
    function GetOnTerminate: TNotifyEvent;
    function GetProcess: TProcess;
    procedure SetOnLine(AValue: TProgramByLineEvent);
    procedure SetOnTerminate(AValue: TNotifyEvent);

    function Terminate(const AExitCode: Integer): Boolean;
    property Process: TProcess read GetProcess;
    property OnTerminate: TNotifyEvent read GetOnTerminate write SetOnTerminate;
    property OnLine: TProgramByLineEvent read GetOnLine write SetOnLine;
  end;

  TStopStreamByLine = function: Boolean of object;
  TStreamByLineEvent = procedure(const ALine: string; const AIsAddToLastLine: Boolean) of object;

  { TStreamByLine }

  TStreamByLine = class(TThread)
  private
    FStopCallBack: TStopStreamByLine;
    FStream: TInputPipeStream;
    FOnLine: TStreamByLineEvent;
    FIsSyncronize: Boolean;
    FLine: string;
    FIsAddToLastLine: Boolean;
    procedure DoLineSync;
  protected
    procedure Execute; override;
  public
    constructor CreateAlt(const AStream: TInputPipeStream; const AOnLine: TStreamByLineEvent;
        const AStopCallBack: TStopStreamByLine = nil;
        const AIsSyncronize: Boolean = False; ACreateSuspended: Boolean = False);
    //property StopCallBack: TStopStreamByLine read FStopCallBack write FStopCallBack;
  end;

function RunProgramByLine(const AProgram: string; const AParams: array of string;
    const AOnLine: TProgramByLineEvent; const AOnTerminate: TNotifyEvent = nil;
    const AIsSyncronize: Boolean = False): IProgramByLine;


implementation

type
    { TProgramByLine }

  TProgramByLine = class(TInterfacedObject, IProgramByLine)
  private
    FProcess: TProcess;
    FOnLine: TProgramByLineEvent;
    FStream: TStreamByLine;
    procedure OnStreamLine(const ALine: string; const AIsAddToLastLine: Boolean);
    function StreamStopProc: Boolean;
  protected
    { IProgramByLine }
    function GetOnLine: TProgramByLineEvent;
    function GetOnTerminate: TNotifyEvent;
    function GetProcess: TProcess;
    procedure SetOnLine(AValue: TProgramByLineEvent);
    procedure SetOnTerminate(AValue: TNotifyEvent);
    function Terminate(const AExitCode: Integer): Boolean;
  public
    constructor Create(const AProgram: string; const AParams: array of string;
      const AOnLine: TProgramByLineEvent;
      const AOnTerminate: TNotifyEvent = nil; const AIsSyncronize: Boolean = False); virtual;
    destructor Destroy; override;

    //property IsSyncronize: Boolean read FIsSyncronize write FIsSyncronize;
    //property Process: TProcess read FProcess;
  end;

{$IFDEF WINDOWS}
function OEMToUTF8(const S: string): string;
var
  Dst: PWideChar;
  ws: WideString;
begin
  Dst := AllocMem((Length(S) + 1) * SizeOf(WideChar));
  if OemToCharW(PChar(s), Dst) then
    begin
      ws := PWideChar(Dst);
      Result := UTF8Encode(ws);
    end
  else
    Result := s;
  FreeMem(Dst);
end;{$ENDIF}

function RunProgramByLine(const AProgram: string;
  const AParams: array of string; const AOnLine: TProgramByLineEvent;
  const AOnTerminate: TNotifyEvent; const AIsSyncronize: Boolean
  ): IProgramByLine;
begin
  Result := TProgramByLine.Create(AProgram, AParams, AOnLine, AOnTerminate, AIsSyncronize);
end;
{ TStreamByLine }

procedure TStreamByLine.DoLineSync;
begin
  FOnLine(FLine, FIsAddToLastLine);
end;

procedure TStreamByLine.Execute;
const
  READ_BYTES = 2048;
var
  sOutput: string;
  sBuf: RawByteString;
  IsNewLine: Boolean = True;

  function _ReadOutput: Boolean;
  var
    NumBytes: LongInt;
  begin
    if FStream.NumBytesAvailable = 0 then Exit(False);
    NumBytes := FStream.Read(sBuf[1], READ_BYTES);
    Result := NumBytes > 0;
    if Result then
      sOutput += Copy(sBuf, 1, NumBytes);
  end;

  procedure _DoLine;
  var
    i: SizeInt;
  begin
    if sOutput = '' then Exit;
    repeat
      FIsAddToLastLine := not IsNewLine;
      i := PosSet([#10, #13], sOutput);
      IsNewLine := i > 0;
      if IsNewLine then
        begin
          FLine := Copy(sOutput, 1, i - 1);
          case sOutput[i] of
            #13:
              if (sOutput[i + 1] = #10) then
                Inc(i);
            #10:
              if (sOutput[i + 1] = #13) then
                Inc(i);
          end;

          Delete(sOutput, 1, i);
        end
      else
        begin
          FLine := sOutput;
          sOutput := '';
        end;

      {$IFDEF WINDOWS}
      if GuessEncoding(FLine) <> EncodingUTF8 then
        FLine := OEMToUTF8(FLine);{$ENDIF}
      if Assigned(FOnLine) then
        if FIsSyncronize then
          Synchronize(@DoLineSync)
        else
          DoLineSync;

    until (sOutput = '');
  end;

begin
  if FStream = nil then Exit;
  SetLength(sBuf, READ_BYTES);
  while not Terminated and
      (not Assigned(FStopCallBack) or not FStopCallBack()) do
    begin
      if not _ReadOutput then
        begin
          _DoLine;
          Sleep(100);
        end;
    end;

  while _ReadOutput do ;
  _DoLine;
end;

constructor TStreamByLine.CreateAlt(const AStream: TInputPipeStream;
  const AOnLine: TStreamByLineEvent; const AStopCallBack: TStopStreamByLine;
  const AIsSyncronize: Boolean; ACreateSuspended: Boolean);
begin
  inherited Create(ACreateSuspended);
  FOnLine := AOnLine;
  FStream := AStream;
  FStopCallBack := AStopCallBack;
  FIsSyncronize := AIsSyncronize;
end;

{ TProgramByLine }

procedure TProgramByLine.OnStreamLine(const ALine: string;
  const AIsAddToLastLine: Boolean);
begin
  if Assigned(FOnLine) then
    FOnLine(Self, ALine, AIsAddToLastLine);
end;

function TProgramByLine.StreamStopProc: Boolean;
begin
  Result := not FProcess.Running;
end;

function TProgramByLine.GetOnLine: TProgramByLineEvent;
begin
  Result := FOnLine;
end;

function TProgramByLine.GetOnTerminate: TNotifyEvent;
begin
  Result := FStream.OnTerminate;
end;

function TProgramByLine.GetProcess: TProcess;
begin
  Result := FProcess;
end;

procedure TProgramByLine.SetOnLine(AValue: TProgramByLineEvent);
begin
  FOnLine := AValue;
end;

procedure TProgramByLine.SetOnTerminate(AValue: TNotifyEvent);
begin
  FStream.OnTerminate := AValue;
end;

function TProgramByLine.Terminate(const AExitCode: Integer): Boolean;
begin
  Result := FProcess.Terminate(AExitCode);
end;

constructor TProgramByLine.Create(const AProgram: string;
  const AParams: array of string; const AOnLine: TProgramByLineEvent;
  const AOnTerminate: TNotifyEvent; const AIsSyncronize: Boolean);
var
  opts: TProcessOptions;
  i: Integer;
begin
  FOnLine := AOnLine;
  //OnTerminate := AOnTerminate;

  opts := [];
  Exclude(opts, poWaitOnExit);
  //Exclude(opts, poUsePipes);
  opts := opts + [poUsePipes, {poNoConsole,} poStderrToOutPut, poNewProcessGroup];

  FProcess := TProcessUTF8.Create(nil);
  FProcess.Executable := AProgram;
  if Length(AParams) > 0 then
    for i := 0 to Length(AParams) - 1 do
      FProcess.Parameters.Add(AParams[i]);
  FProcess.Options := opts;
  //FProcess.ShowWindow := swoHIDE;
  try
    FProcess.Execute;
    FStream := TStreamByLine.CreateAlt(FProcess.Output, @OnStreamLine, @StreamStopProc, AIsSyncronize);
    FStream.OnTerminate := AOnTerminate;
  except
    if FStream = nil then
      FStream := TStreamByLine.CreateAlt(nil, nil);
  end;
end;

destructor TProgramByLine.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

end.

