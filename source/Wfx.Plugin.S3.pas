unit Wfx.Plugin.S3;

interface

uses
  System.SysUtils,
  System.Classes,
  System.AnsiStrings,
  System.IOUtils,
  System.Generics.Collections,
  System.IniFiles,
  System.TypInfo,
  WinApi.ShFolder,

  WinApi.Windows,
  WinApi.Messages,

  Data.Cloud.CloudAPI,
  Data.Cloud.AmazonAPI,

  Wfx.Plugin.intf,
  Wfx.Plugin.Base,
  Wfx.Plugin.Consts,
  Wfx.Plugin.S3.Path,
  Wfx.Plugin.S3.Client, Vcl.Dialogs;

type
  TPluginMode = ( pmInit, pmPickProfile, pmPickBucket, pmShowFolderContents );
  TS3Plugin = class(TWFXPlugin, IWfxPlugin)
  const
    PLUGIN_NAME = 'S3';
  private
    procedure ConnectToS3;
    function  GetCredentialsFilePath: string;
  protected
    FConnectionInfo: TAmazonConnectionInfo;
    FS3            : IS3Client;
    FClientFactory : TS3ClientFactory;
    /// Empty means "derive from the current user profile". Tests inject a
    /// fixture path so they never read the developer's real ~/.aws/credentials.
    FCredentialsFilePath: string;
    FBuckets       : TStrings;
    FRegion        : string;
    FCurrentPath   : string;
    Path           : TS3TcPath;
    FProfile       : string;
    FPickProfile   : TFileInfo;
    PluginMode     : TPluginMode;
    FProfiles      : TStringList;
  public
    constructor Create; override;
    /// Test seam. Pass nil for aClientFactory to get the production factory,
    /// and '' for aCredentialsFilePath to use the real ~/.aws/credentials.
    constructor CreateInjected(const aClientFactory: TS3ClientFactory;
                               const aCredentialsFilePath: string);
    destructor Destroy; override;
    procedure Init; override;
    function GetPluginName: string;override;
    function GetUserPath:string;
    function FindFileInfo(aRemoteName: string; var fi:TFileInfo):boolean;
    function ExecuteFile(aMainWin: THandle; aRemoteName, aVerb: string): Integer; override;
    function FindFirstFile(var aFindData: TWin32FindData; aPath: string): THandle; override;
    function GetFile(aRemoteName: string; aLocalName: string): Integer;override;
    function GetIcon(aRemoteName: string; ExtractFlags: Integer; var TheIcon: HICON): Integer;override;
    function Delete(const aRemoteName: string): Boolean; override;
    function MkDir(aRemoteDir:String):Boolean;override;
    function RenMovFile(aOldName,aNewName:String;aMove,aOverWrite:Boolean; aRemoteInfo:pRemoteInfo):integer;override;
    function PutFile(aLocalName,aRemoteName:String;aCopyFlags:integer):integer;override;
    function RemoveDir(aRemoteName:String):Boolean;override;
    function Disconnect(aDisconnectRoot:String):Boolean;override;
    function GetLocalName(var aRemoteName:String;maxlen:integer):Boolean;override;
  end;

implementation

function ISO8601ToDateTime(Value: String):TDateTime;
var
  fs: TFormatSettings;
begin
  fs := TFormatSettings.Create(GetThreadLocale);
  fs.DateSeparator := '-';
  fs.ShortDateFormat := 'yyyy-MM-dd';
  Value := Value.Replace('T', ' ').Replace('Z','').Substring(0,19);
  Result := StrToDateTime(Value, fs);
end;

function TS3Plugin.GetCredentialsFilePath: string;
begin
  if FCredentialsFilePath <> '' then
    Exit(FCredentialsFilePath);

  const awsPath = GetUserPath;
  Result := TPath.Combine(TPath.Combine(awsPath,'.aws'),'credentials');
end;

procedure TS3Plugin.ConnectToS3;
begin
  const credentials = GetCredentialsFilePath;

  FProfiles.Free;
  FProfiles := TStringList.Create;
  var AccountName := '';
  var AccountKey := '';

  if TFile.Exists(credentials) then
  begin
    const ini = TIniFile.Create(credentials);
    try
      AccountName  := ini.ReadString(FProfile,'aws_access_key_id',AccountName);
      AccountKey   := ini.ReadString(FProfile,'aws_secret_access_key',AccountKey);
      FRegion      := ini.ReadString(FProfile,'region',FRegion);
      ini.ReadSections(FProfiles);
    finally
      ini.Free;
    end;
  end;

  // Release the old client BEFORE freeing the connection info it points at.
  // The previous code freed FConnectionInfo while the old service still held it.
  FS3 := nil;
  FConnectionInfo.Free;
  FConnectionInfo             := TAmazonConnectionInfo.Create(nil);
  FConnectionInfo.AccountName := AccountName;
  FConnectionInfo.AccountKey  := AccountKey;
  FConnectionInfo.Region      := FREgion;
  FS3                         := FClientFactory(FConnectionInfo);

  if (AccountName = '') or
     (AccountKey = '') or
     (FRegion = '') then
    PluginMode := TPluginMode.pmPickProfile
  else
    PluginMode := TPluginMode.pmPickBucket;


end;

constructor TS3Plugin.Create;
begin
  CreateInjected(nil, '');
end;

constructor TS3Plugin.CreateInjected(const aClientFactory: TS3ClientFactory;
                                     const aCredentialsFilePath: string);
begin
  inherited Create;

  if Assigned(aClientFactory) then
    FClientFactory := aClientFactory
  else
    FClientFactory := DefaultS3ClientFactory;

  FCredentialsFilePath := aCredentialsFilePath;

  PluginMode := TPluginMode.pmInit;
  FProfiles := TStringList.Create;
  FBuckets := TStringList.Create;

end;

function TS3Plugin.Delete(const aRemoteName: string): Boolean;
var res:TCloudResponseInfo;
begin
  res := TCloudResponseInfo.Create;
  try
    // The bucket comes from the path being acted on, never from whichever
    // bucket happened to be browsed last.
    const LBucket = Path.GetBucketName(aRemoteName);

    if Path.IsBucket(aRemoteName) then
      Result := FS3.DeleteBucket(LBucket, res, FRegion)
    else
      Result := FS3.DeleteObject(LBucket, Path.ToS3Key(aRemoteName), res, FRegion);
  finally
    LogDebug(res.StatusMessage);
    res.Free;
  end;
end;

destructor TS3Plugin.Destroy;
begin
  FBuckets.Free;
  FProfiles.Free;
  // Release the client before the connection info it points at.
  FS3 := nil;
  FConnectionInfo.Free;
  inherited;
end;

function TS3Plugin.Disconnect(aDisconnectRoot: String): Boolean;
begin
  inherited;
  Result := false;
end;

function TS3Plugin.ExecuteFile(aMainWin: THandle; aRemoteName, aVerb: string): Integer;
begin
  try
    var f:TFileinfo;
    if not self.FindFileInfo(aRemoteName, f) then
      Exit(FS_EXEC_ERROR);

    if f.FileType = TFileType.ftAction then
    begin
      if Assigned(f.OnExecute) then
        f.OnExecute(aMainWin, aRemoteName, aVerb, @f);
    end;
    Result := FS_EXEC_OK;
  except
    on E: Exception do
    begin
      Result := FS_EXEC_ERROR;
      TCShowMessage('', E.Message);
    end;
  end;
end;

function TS3Plugin.FindFileInfo(aRemoteName: string; var fi:TFileInfo):boolean;
begin
  const a = aRemoteName.Split(['\']);

  var l := '';
  if length(a)>0 then
    l := a[high(a)]
  else
    l := aRemoteName;

  for var f in FFileList do
  begin
    if f.FileName = l then
    begin
      fi := f;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TS3Plugin.FindFirstFile(var aFindData: TWin32FindData; aPath: string): THandle;
begin
  FCurrentPath := aPath;

  FFileList.Clear;

  if pluginMode=TPluginMode.pmShowFolderContents then
    if Path.IsRoot(FCurrentPath) then
      PluginMode := TPluginMode.pmPickBucket;

  case pluginMode of
    pmInit:
      FFileList.Add(FPickProfile);

    pmPickProfile:
      begin
        for var p in FProfiles do
        begin
          var f := TFileInfo.Create;
          f.FileName := p;
          f.IsVirtual := True;
          f.OnExecute :=
            procedure(aMainWin: THandle; aRemoteName, aVerb: string; sender:PFileInfo)
            begin
              const a = aRemoteName.Split(['\']);

              var l := '';
              if length(a)>0 then
                l := a[high(a)]
              else
                l := aRemoteName;

              PluginMode := TPluginMode.pmPickBucket;

              FProfile := l;
              ConnectToS3;
              RefreshTc(aMainWin);
            end;
          f.FileType := TFileType.ftAction;

          FFileList.Add(f);
        end;
      end;
    pmPickBucket:
      begin
        FFileList.Add(FPickProfile);
        FBuckets.Free; // ListBuckets hands back a list we own
        FBuckets := FS3.ListBuckets;
        LogDebug('Retrieved bucket list');
        for var bucketName in FBuckets do
        begin
          var FileInfo:= TFileInfo.Create;
          var item := bucketName.Split(['=']);
          if length(item) = 2 then
          begin
            FileInfo.FileName := item[0];
            FileInfo.Date := ISO8601ToDateTime(item[1]);
          end
          else
          begin
            FileInfo.FileName := bucketName;
            FileInfo.Date := 0;
          end;

          FileInfo.Directory := '';
          FileInfo.ReadOnly := True;
          FileInfo.Size := 0;
          FileInfo.FileType := TFileType.ftDir;
          FileInfo.OnExecute :=
            procedure(aMainWin: THandle; aRemoteName, aVerb: string; sender:PFileInfo)
            begin
              PluginMode := TPluginMode.pmShowFolderContents;
            end;
          FFileList.Add(FileInfo);
        end;
        FFileListIndex := 0;
        PluginMode := TPluginMode.pmShowFolderContents;
      end;
    pmShowFolderContents:
      begin
        const LBucketName = Path.GetBucketName(FCurrentPath);
        const LDirectory = Path.GetPrefix(FCurrentPath);
        var res := TCloudResponseInfo.Create;
        var params := TStringList.Create;
        params.AddPair('prefix', LDirectory );

        var LBucketResult := FS3.GetBucket(LBucketName, params, res, FRegion);

        if LBucketResult <> nil then
        begin
          for var o in LBucketResult.Objects do
          begin
            if o.Name = LDirectory then
              Continue;

            var FileInfo:= TFileInfo.Create;
            var Name := o.Name.TrimRight(['/']).Replace('/','\');

            FileInfo.Directory := LBucketResult.RequestPrefix;
            FileInfo.Date := ISO8601ToDateTime(o.LastModified);
            FileInfo.Size := o.Size;
            if o.Name.EndsWith('/') then
              FileInfo.FileType := TFileType.ftDir
            else
              FileInfo.FileType := TFileType.ftFile;

            FileInfo.ReadOnly := false;
            const prefix = ExtractFilePath(Name).Replace('\','/');
            if prefix <> LBucketResult.RequestPrefix then
              Continue;

            FileInfo.FileName  := Name.Substring(length(Prefix),MaxInt);

            FFileList.Add(fileInfo);
          end;
        end
        else
          TCShowMessage('Error', res.StatusMessage );

        res.Free;
      end;


  end;


  if FFileList.Count > 0 then
  begin
    FFileListIndex := 0;
    BuildFindData(aFindData, FFileList[0]);
  end
  else
  begin
    FFileListIndex := -1;
  end;
  Result := 1;

end;

procedure TS3Plugin.Init;
begin
  inherited;

  FProfile := 'default';
  FRegion := 'eu-west-1';
  FPickProfile.FileName := '[PICK AWS PROFILE]';

  FPickProfile.FileType := TFileType.ftAction;
  FPickProfile.ReadOnly := True;
  FPickProfile.Size := 0;
  FPickProfile.OnExecute :=
    procedure(aMainWin: THandle; aRemoteName, aVerb: string; sender:PFileInfo)
    begin
      PluginMode := TPluginMode.pmPickProfile;
      RefreshTc(aMainWin);
    end;

  PluginMode := TPluginMode.pmPickProfile;

  ConnectToS3;

  FBuckets.Free;
  FBuckets := TStringList.Create;
end;

function TS3Plugin.MkDir(aRemoteDir: String): Boolean;
var res:TCloudResponseInfo;
begin
  res := TCloudResponseInfo.Create;
  try
    // The previous version ended in an unconditional Exit(True), discarding
    // both results - a failed bucket or folder creation looked like a success.
    if Path.IsBucket(aRemoteDir) then
      // at the root, so create a bucket
      Result := FS3.CreateBucket(Path.GetBucketName(aRemoteDir),
                  TAmazonACLType.amzbaPrivate, FRegion, res)
    else
      // inside a bucket, so create a folder marker
      Result := FS3.UploadObject(Path.GetBucketName(aRemoteDir),
                  Path.ToS3Key(aRemoteDir) + '/', [], False, nil, nil,
                  TAmazonACLType.amzbaNotSpecified, res, FRegion);

    if not Result then
      LogDebug('MkDir failed: ' + res.StatusMessage);
  finally
    res.Free;
  end;
end;

function TS3Plugin.PutFile(aLocalName, aRemoteName: String; aCopyFlags: integer): integer;
var res:TCloudResponseInfo;
begin
  const LBucket = Path.GetBucketName(aRemoteName);
  if LBucket = '' then
  begin
    TCShowMessage('Cannot upload file', 'Select a bucket first');
    Exit(FS_FILE_NOTSUPPORTED);
  end;

  res := TCloudResponseInfo.Create;
  try
    try
      // UploadObject's result used to be discarded, so a rejected upload was
      // reported to TC as a success.
      if FS3.UploadObject(LBucket, Path.ToS3Key(aRemoteName),
           TFile.ReadAllBytes(aLocalName), False, nil, nil,
           TAmazonACLType.amzbaNotSpecified, res, FRegion) then
        Result := FS_FILE_OK
      else
      begin
        LogDebug('PutFile failed: ' + res.StatusMessage);
        Result := FS_FILE_WRITEERROR;
      end;
    except
      Result := FS_FILE_WRITEERROR;
    end;
  finally
    res.Free;
  end;
end;



function TS3Plugin.GetPluginName: string;
begin
  Result := PLUGIN_NAME;
end;

function TS3Plugin.RemoveDir(aRemoteName: String): Boolean;
begin
  Result := Delete(aRemoteName);
end;

function TS3Plugin.RenMovFile(aOldName, aNewName: String; aMove, aOverWrite: Boolean; aRemoteInfo: pRemoteInfo): integer;
begin
  try
    // S3 has no rename: copy the object, then delete the original - but ONLY
    // for a move, and ONLY once the copy is confirmed. The previous version
    // ignored aMove entirely and deleted whenever source and target buckets
    // matched, so an ordinary copy destroyed its own source.
    var oldName := Path.ToS3Key(aOldName);
    var oldBucket := Path.GetBucketName(aOldName);
    var newName := Path.ToS3Key(aNewName);
    var newBucket := Path.GetBucketName(aNewName);

    if not FS3.CopyObject(newBucket, newName, oldBucket, oldName, nil, nil, FRegion) then
      Exit(FS_FILE_WRITEERROR);

    if aMove then
      if not FS3.DeleteObject(oldBucket, oldName, nil, FRegion) then
        Exit(FS_FILE_WRITEERROR);

    Result := FS_FILE_OK;
  except
    Result := FS_FILE_WRITEERROR;
  end;
end;

function TS3Plugin.GetUserPath: string;
var
  LStr: array[0 .. MAX_PATH] of Char;
begin
  const CSIDL_PROFILE = $28;
  SetLastError(ERROR_SUCCESS);
  if SHGetFolderPath(0, CSIDL_PROFILE, 0, 0, @LStr) = S_OK then
    Result := LStr;
end;

function TS3Plugin.GetFile(aRemoteName, aLocalName: string): Integer;
begin
  try
    if Path.IsRoot(FCurrentPath) then
      Exit(FS_FILE_NOTSUPPORTED);

    if AbortCopy then
      Exit(FS_FILE_USERABORT);

    var s := TFileStream.Create(aLocalName, fmCreate);
    try
      var params := TAmazonGetObjectOptionals.Create;

      // Previously a trailing unconditional 'Result := FS_FILE_OK' overwrote
      // this, so every failed download was reported to TC as a success - and a
      // move-from-S3 then deleted the remote object.
      if FS3.GetObject(Path.GetBucketName(aRemoteName), Path.ToS3Key(aRemoteName),
                       params, s, nil, FRegion) then
        Result := FS_FILE_OK
      else
        Result := FS_FILE_READERROR;
    finally
      s.Free;
    end;

    // Do not leave a half-written or empty file behind on failure.
    if (Result <> FS_FILE_OK) and TFile.Exists(aLocalName) then
      TFile.Delete(aLocalName);
  except
    on E: Exception do
    begin
      Result := FS_FILE_READERROR;
      TCShowMessage('', E.Message);
    end;
  end;
end;

function TS3Plugin.GetIcon(aRemoteName: string; ExtractFlags: Integer; var TheIcon: HICON): Integer;
begin
  Result := FS_ICON_USEDEFAULT;
  if aRemoteName.EndsWith('\..\') then
    Exit;

   if Path.IsRoot(aRemoteName) then
  begin
    TheIcon := LoadIcon(HInstance, 'BUCKET');
    Result  := FS_ICON_EXTRACTED;
    Exit;
  end;

  var fi:= TFileInfo.Create;
  if FindFileInfo(aRemoteName, fi) then
  if fi.FileType = TFileType.ftAction then

  begin
    TheIcon := LoadIcon(HInstance, 'CONFIG');
    Result  := FS_ICON_EXTRACTED;
    Exit;
  end;

  if Path.IsBucket(aRemoteName) then
  begin
    TheIcon := LoadIcon(HInstance, 'BUCKET');
    Result  := FS_ICON_EXTRACTED;
    Exit;
  end;

end;

function TS3Plugin.GetLocalName(var aRemoteName: String; maxlen: integer): Boolean;
begin
  Result := True;
end;




initialization
  globalPluginFactory :=
    function:IWfxPlugin
    begin
      Result := TS3Plugin.Create;
    end;

end.
