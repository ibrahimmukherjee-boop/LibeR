#ifndef StageDir
  #error StageDir must be supplied with /DStageDir=...
#endif
#ifndef OutputDir
  #error OutputDir must be supplied with /DOutputDir=...
#endif
#ifndef AppVersion
  #define AppVersion "development"
#endif
#ifndef InstallerProfile
  #define InstallerProfile "research"
#endif
#ifndef VersionInfoVersion
  #define VersionInfoVersion "0.0.0.0"
#endif
#if InstallerProfile == "runtime"
  #define LauncherFlags "runminimized closeonexit"
#else
  #define LauncherFlags "closeonexit"
#endif

#define AppName "LibeR Ecosystem"
#define Publisher "Sven C. van Dijkman"

[Setup]
AppId=LibeR-Ecosystem-{#AppVersion}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
VersionInfoVersion={#VersionInfoVersion}
DefaultDirName={localappdata}\Programs\LibeR\{#AppVersion}
DefaultGroupName=LibeR {#AppVersion}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=LibeR-{#AppVersion}-{#InstallerProfile}-windows-x86_64
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern
SetupIconFile=liber.ico
UninstallDisplayIcon={app}\app\liber.ico
ChangesAssociations=no
CloseApplications=yes
RestartApplications=no

[Types]
#if InstallerProfile == "research"
Name: "full"; Description: "Research installation (runtime and developer SDK)"
Name: "runtime"; Description: "Runtime only"
Name: "custom"; Description: "Custom installation"; Flags: iscustom
#else
Name: "runtime"; Description: "Runtime"
Name: "custom"; Description: "Custom installation"; Flags: iscustom
#endif

[Components]
#if InstallerProfile == "research"
Name: "runtime"; Description: "LibeR private R runtime and applications"; Types: full runtime custom; Flags: fixed
Name: "developer"; Description: "Developer headers and source archives"; Types: full
#else
Name: "runtime"; Description: "LibeR private R runtime and applications"; Types: runtime custom; Flags: fixed
#endif

[Files]
Source: "{#StageDir}\runtime\*"; DestDir: "{app}\runtime"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: runtime
Source: "{#StageDir}\library\*"; DestDir: "{app}\library"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: runtime
Source: "{#StageDir}\app\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: runtime
Source: "{#StageDir}\build-plan.json"; DestDir: "{app}"; Flags: ignoreversion; Components: runtime
Source: "{#StageDir}\package-manifest.csv"; DestDir: "{app}"; Flags: ignoreversion; Components: runtime
Source: "{#StageDir}\files.csv"; DestDir: "{app}"; Flags: ignoreversion; Components: runtime
#if InstallerProfile == "research"
Source: "{#StageDir}\developer\*"; DestDir: "{app}\developer"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist; Components: developer
#endif

[Icons]
Name: "{group}\LibeRation"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\launch.R"" liberation"; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\LibeRality"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\launch.R"" liberality"; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\LibeRator"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\launch.R"" liberator"; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\LibeRtAD"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\launch.R"" libertad"; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\LibeRary"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\launch.R"" liberary"; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\LibeRary Ingest"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\launch.R"" liberary-ingest"; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\LibeRary Reference"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\launch.R"" liberary-reference"; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\LibeRties Admin"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\launch.R"" liberties"; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\Validate installation"; Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\doctor.R"""; WorkingDir: "{app}"; IconFilename: "{app}\app\liber.ico"; Flags: {#LauncherFlags}
Name: "{group}\Uninstall LibeR"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\runtime\R\bin\Rscript.exe"; Parameters: "--vanilla ""{app}\app\doctor.R"""; Description: "Validate the LibeR installation"; Flags: postinstall nowait skipifsilent unchecked

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
