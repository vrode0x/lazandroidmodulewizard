unit AndroidGdb;

{$mode objfpc}{$H+}

{
How manually start debugging
Server:
  adb forward tcp:5039 tcp:5039
  adb shell
	  >ps #list of pid
	  >gdbserver :5039 --attach <pid>

Client:
  path\to\ndk\\toolchains\x86-4.9\prebuilt\windows\bin\i686-linux-android-gdb.exe
	  >target remote:5039
	  >set sysroot  invalid\path
	  >set solib-search-path directory\\of\\target\\filename

}

interface
{.$DEFINE TEST_MODE}
uses
  Classes, SysUtils, GDBMIServerDebugger, GDBMIDebugger, DbgIntfDebuggerBase,
  ProjectIntf, Forms, Dialogs, LCLStrConsts, process, LazStringUtils,
  LazFileUtils, LazUTF8Classes, laz2_XMLRead, Laz2_DOM, UTF8Process, UITypes,
  LazIDEIntf, IDEMsgIntf, LamwSettings, ApkBuild, strutils;

type
  { TAndroidGDBMIDebuggerCommandStartDebugging }

  TAndroidGDBMIDebuggerCommandStartDebugging = class(TGDBMIDebuggerCommandStartDebugging)
  private
  protected
    function  GdbRunCommand: TGDBMIExecCommandType; override;
    function DoExecute: Boolean; override;
    function DoChangeFilename: Boolean; override;
  end;

  { TAndroidDebugger }

  TAndroidDebugger = class(TGDBMIServerDebugger)
  private
    FAdb: TProcessUTF8;
    function OnProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    function StartGdbServer: Boolean;
    procedure OnInitCmdExecuted(Sender: TObject);
    procedure ExecuteSimpleCommand(const ACommand: string);
    procedure OnStartCmdExecuted(Sender: TObject);
  protected
    function CreateCommandInit: TGDBMIDebuggerCommandInitDebugger; override;
    function CreateCommandStartDebugging(AContinueCommand: TGDBMIDebuggerCommand): TGDBMIDebuggerCommandStartDebugging; override;
    function RequestCommand(const ACommand: TDBGCommand;
      const AParams: array of const; const ACallback: TMethod): Boolean; override;
  public
    constructor Create(const AExternalDebugger: String); override;
    destructor Destroy; override;

    procedure Init; override;
    class function Caption: String; override;
    class function NeedsExePath: boolean; override;
  end;

procedure Register;

implementation

type

  { TDummyGDBMIDebuggerCommandInitDebugger }

  TDummyGDBMIDebuggerCommandInitDebugger = class(TGDBMIDebuggerCommandInitDebugger)
  protected
    function DoExecute: Boolean; override;
  end;


{ TDummyGDBMIDebuggerCommandInitDebugger }

function TDummyGDBMIDebuggerCommandInitDebugger.DoExecute: Boolean;
begin
  Result := False;
end;

procedure Register;
begin
  RegisterDebugger(TAndroidDebugger);
end;

{ TAndroidGDBMIDebuggerCommandStartDebugging }

function TAndroidGDBMIDebuggerCommandStartDebugging.GdbRunCommand: TGDBMIExecCommandType;
begin
  Result := ectContinue;//'-exec-continue';
end;

function TAndroidGDBMIDebuggerCommandStartDebugging.DoExecute: Boolean;
begin
  DebuggerProperties.InternalStartBreak := gdbsNone;
  Result := inherited DoExecute;
end;

function TAndroidGDBMIDebuggerCommandStartDebugging.DoChangeFilename: Boolean;
begin
  Result := True;
end;

{ TAndroidDebugger }

function TAndroidDebugger.StartGdbServer: Boolean;
var
  Props: TGDBMIServerDebuggerProperties;
  xml: TXMLDocument;
  sProjPath, sManifest, sPackageName, sAdbExe: String;
  iPort: LongInt;

  function _GetPid(out APid: string): Boolean;
  var
    S: string;
  begin
    Result := False;
    RunCommand(sAdbExe, ['shell', 'ps|grep', sPackageName], S, []);
    S := Trim(S);
    if AnsiEndsStr(sPackageName, S) then
      begin
        APid := ExtractWord(2, S, [' ']);
        Result := IsNumber(APid);
      end
  end;

  function _RunApk: Boolean;
  begin
    Result := False;
    //try
    //  IDEMessagesWindow.BringToFront;
    //  with TApkBuilder.Create(LazarusIDE.ActiveProject) do
    //    try
    //      if BuildAPK then
    //        begin
    //          RunAPK;
    //          Result := True;
    //        end;
    //    finally
    //      Free;
    //    end;
    //except end;
  end;

var
  S, sPid: string;
begin
  Result := False;
    sAdbExe := IncludeTrailingPathDelimiter(LamwGlobalSettings.PathToAndroidSDK) +
      {$IFDEF WINDOWS}'platform-tools\adb.exe'{$ELSE}'platform-tools/adb'{$ENDIF};
  if not FileExistsUTF8(sAdbExe) then
    begin
      MessageDlg(Format(rsfdFileNotExist, [sAdbExe]), mtError, [mbOK], 0);
      Exit;
    end;

  Props := TGDBMIServerDebuggerProperties(GetProperties);
  sProjPath := ExtractFilePath(ExtractFileDir(LazarusIDE.ActiveProject.MainFile.Filename));
  sManifest := sProjPath + 'AndroidManifest.xml';
  ReadXMLFile(xml, sManifest);
  try
    sPackageName := xml.DocumentElement.AttribStrings['package'];
    if sPackageName = '' then
      raise Exception.Create('Cannot determine package name!');
  finally
    xml.Free;
  end;

  iPort := StrToIntDef(Props.Debugger_Remote_Port, 5039);
  ExecuteProcess(sAdbExe, Format('forward tcp:%d tcp:%d', [iPort, iPort]));
  if not _GetPid(sPid) then
      if not _RunApk or not _GetPid(sPid) then
    begin
      MessageDlg(Format('"%s" is not running', [sPackageName]), mtError, [mbOK], 0);
      Exit;
    end;

  FAdb := TProcessUTF8.Create(nil);
  FAdb.ParseCmdLine(Format('adb shell gdbserver %s:%d --attach %s',
      [Props.Debugger_Remote_Hostname, iPort, sPid]));
  FAdb.Executable := sAdbExe;
  {$IFNDEF TEST_MODE}
  FAdb.ShowWindow := swoHIDE;{$ENDIF}
  FAdb.Execute;

  Result := FAdb.Running;
  if not Result then
    begin
      if FAdb.Output.Size > 0 then
        begin
          SetLength(S, FAdb.Output.Size);
          FAdb.Output.Position := 0;
          FAdb.Output.Read(S[1], Length(S));
        end
      else
        S := 'Error starting GdbServer';
      MessageDlg(S, mtError, [mbOK], 0);
    end;
end;

function TAndroidDebugger.OnProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
var
  Mode: TAbstractRunParamsOptionsMode;
begin
  Result := mrOK;
  if not FileExistsUTF8(ExtractFilePath(ExtractFileDir(AProject.MainFile.Filename)) +
      'AndroidManifest.xml') then Exit;
  Mode := AProject.RunParameters.Find(AProject.RunParameters.ActiveModeName);
  if (Mode <> nil) and
      (Mode.HostApplicationFilename = '') then
    Mode.HostApplicationFilename := 'dummy';
end;

procedure TAndroidDebugger.OnInitCmdExecuted(Sender: TObject);
var
  sDir: String;
begin
  ExecuteSimpleCommand('set sysroot invalid\\path');
  sDir := ExtractFileDir(ExpandFileNameUTF8(
      LazarusIDE.ActiveProject.LazCompilerOptions.TargetFilename,
      ExtractFileDir(LazarusIDE.ActiveProject.MainFile.Filename)));
  if Pos(' ', sDir) > 0 then
    sDir := '"' + sDir + '"';
  {$IFDEF WINDOWS}
  sDir := StringReplace(sDir, '\', '\\', [rfReplaceAll]);{$ENDIF}
  ExecuteSimpleCommand('set solib-search-path ' + sDir);
end;

procedure TAndroidDebugger.ExecuteSimpleCommand(const ACommand: string);
begin
  QueueCommand(TGDBMIDebuggerSimpleCommand.Create(Self, ACommand, [],
      [cfTryAsync, cfNoThreadContext, cfNoStackContext, cfscIgnoreError, cfscIgnoreState],
      nil, 0));
end;

procedure TAndroidDebugger.OnStartCmdExecuted(Sender: TObject);
begin
  if (State <> dsRun) then
    SetState(dsRun);
end;

function TAndroidDebugger.CreateCommandInit: TGDBMIDebuggerCommandInitDebugger;
begin
  if StartGdbServer then
    begin
      Result := inherited CreateCommandInit;
      Result.OnExecuted := @OnInitCmdExecuted;
    end
  else
    Result := TDummyGDBMIDebuggerCommandInitDebugger.Create(Self);
end;

function TAndroidDebugger.CreateCommandStartDebugging(
  AContinueCommand: TGDBMIDebuggerCommand): TGDBMIDebuggerCommandStartDebugging;
begin
  Result:= TAndroidGDBMIDebuggerCommandStartDebugging.Create(Self, AContinueCommand);
  Result.OnExecuted := @OnStartCmdExecuted;
end;

function TAndroidDebugger.RequestCommand(const ACommand: TDBGCommand;
  const AParams: array of const; const ACallback: TMethod): Boolean;
begin
  LockRelease;
  try
    {%H-}case ACommand of
      dcRun:
        if State = dsStop then
          begin
            WorkingDir := '';
          end;
      dcStop:
        begin
          Result := inherited RequestCommand(dcDetach, AParams, ACallback);
          Exit;
        end;
    end;

    Result := inherited RequestCommand(ACommand, AParams, ACallback);

  finally
    UnlockRelease;
  end;
end;

constructor TAndroidDebugger.Create(const AExternalDebugger: String);
var
  sOS, sExt: string;

  function _Get11(ADebuggerNdk: string = ''): string;
  var
    sTargetCpu, sCpu, sGdbPrefix: String;
  begin
    if AExternalDebugger = '' then
      begin
        {$IFDEF WINDOWS}
        Result := 'toolchains\%s-4.9\prebuilt\%s\bin\%s-gdb%s';
        sOS := 'windows';
        sExt := '.exe';{$ELSE}
        Result := 'toolchains/%s-4.9/prebuilt/%s/bin';
        sOS := 'linux-x86_64';
        sExt := '';
        {$ENDIF}
        sTargetCpu := LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU;
        if sTargetCpu = 'i386' then
          begin
            sCpu := 'x86';
            sGdbPrefix := 'i686-linux-android';
          end
        else if sTargetCpu = 'x86_64' then
          begin
            sCpu := sTargetCpu;
            sGdbPrefix := 'x86_64-linux-android';
          end
        else if sTargetCpu = 'arm' then
          begin
            sCpu := 'arm-linux-androideabi';
            sGdbPrefix := sCpu;
          end
        else if sTargetCpu = 'aarch64' then
          begin
            sCpu := 'aarch64-linux-android';
            sGdbPrefix := sCpu;
          end
        else if sTargetCpu = 'mipsel' then
          begin
            sCpu := 'mipsel-linux-android';
            sGdbPrefix := sCpu;
          end;
        //else if sTargetCpu = 'mips64el' then
        //  sCpu := 'mips64el-linux-android'
        ;
        Result := Format(Result, [sCpu, sOS, sGdbPrefix, sExt]);
        if not DirectoryExistsUTF8(ADebuggerNdk) then
          ADebuggerNdk := LamwGlobalSettings.PathToAndroidNDK;
        Result := IncludeTrailingPathDelimiter(ADebuggerNdk) + Result;
      end
    else
      Result := AExternalDebugger;
  end;

  function _Get12: string;
  begin
    Result := IncludeTrailingPathDelimiter(LamwGlobalSettings.PathToAndroidNDK) +
      //sOS + //ToDo if r21 + '-x86_64'
      {$IFDEF WINDOWS}'prebuilt\windows\bin\gdb.exe'{$ELSE}
      'prebuilt/linux-x86_64/bin/gdb'{$ENDIF};
  end;

var
  sNdk, sDebugger: String;
begin
  {$IFDEF WINDOWS}
  sOS := 'windows';
  sExt := '.exe';{$ELSE}
  sOS := 'linux-x86_64';
  sExt := '';
  {$ENDIF}
  sNdk := LamwGlobalSettings.GetNDK;
  if sNdk = '5' then //>11
    //sDebugger := _Get12
    sDebugger := _Get11('X:\lib\android-ndk\r10e')
  else
    sDebugger := _Get11;
  inherited Create(sDebugger);
end;


destructor TAndroidDebugger.Destroy;
begin
  if FAdb <> nil then
    begin
      FAdb.Terminate(0);
      FAdb.Free;
    end;
  inherited Destroy;
end;

procedure TAndroidDebugger.Init;
begin
  inherited Init;
end;

class function TAndroidDebugger.Caption: String;
begin
  Result := 'GNU debugger (gdb) for Android';
end;

class function TAndroidDebugger.NeedsExePath: boolean;
begin
  Result := False;
end;

procedure _OnBoot;
begin
  LazarusIDE.AddHandlerOnProjectOpened(@TAndroidDebugger(nil).OnProjectOpened);
end;

initialization
  AddBootHandler(libhEnvironmentOptionsLoaded, @_OnBoot);

end.

