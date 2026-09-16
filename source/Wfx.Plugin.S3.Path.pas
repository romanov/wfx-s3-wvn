unit Wfx.Plugin.S3.Path;

interface

type
  /// <summary>
  ///  Translates Total Commander remote names into S3 bucket names and object keys.
  ///
  ///  Input contract (see test/Wfx.Plugin.S3.Path.tests.pas for the full table):
  ///    root                 '\'
  ///    bucket               '\mybucket'      (FsFindFirstW passes no trailing slash)
  ///    folder               '\mybucket\folder'
  ///    file                 '\mybucket\folder\file.txt'
  ///  S3 keys use '/' and carry no leading separator.
  ///
  ///  Every operation is a pure function of the remote name: the first path
  ///  segment is always the bucket, everything after it is the key. The record
  ///  deliberately holds no state - an earlier version cached a bucket name and
  ///  used it for substring replacement, which corrupted any key that happened
  ///  to contain the bucket name.
  /// </summary>
  TS3TcPath = record
  private
    /// Path segments with separators and empties removed.
    function Segments(const aRemoteName: string): TArray<string>;
  public
    function IsRoot(const aRemoteName:string): Boolean;
    function IsBucket(const aRemoteName:string): Boolean;
    function GetBucketName(const aRemoteName:string):string;
    /// The S3 object key: everything after the leading bucket segment.
    function ToS3Key(const aRemoteName:string):string;
    /// The S3 listing prefix for a folder: ToS3Key plus a trailing '/'.
    function GetPrefix(const aRemoteName:string):string;
  end;

implementation

uses
  System.SysUtils
;


{ TS3TcPath }

function TS3TcPath.Segments(const aRemoteName: string): TArray<string>;
begin
  Result := [];
  for var LPart in aRemoteName.Split(['\']) do
    if LPart <> '' then
      Result := Result + [LPart];
end;

function TS3TcPath.GetBucketName(const aRemoteName: string): string;
begin
  const LSegments = Segments(aRemoteName);
  if Length(LSegments) > 0 then
    Result := LSegments[0]
  else
    Result := '';
end;

function TS3TcPath.ToS3Key(const aRemoteName: string): string;
begin
  const LSegments = Segments(aRemoteName);

  // Drop segment 0 (the bucket) and join the rest with '/'. Note this is a
  // structural drop, NOT a substring replacement - '\data\data-report.csv'
  // must yield 'data-report.csv', not '-report.csv'.
  Result := '';
  for var i := 1 to High(LSegments) do
  begin
    if Result <> '' then
      Result := Result + '/';
    Result := Result + LSegments[i];
  end;
end;

function TS3TcPath.IsRoot(const aRemoteName: string): Boolean;
begin
  Result := aRemoteName = '\';
end;

function TS3TcPath.IsBucket(const aRemoteName: string): Boolean;
begin
  // Exactly one segment means a bucket root, whether or not Total Commander
  // appended a trailing backslash. Accepting both forms means bucket removal
  // works regardless of which one FsRemoveDirW receives.
  Result := Length(Segments(aRemoteName)) = 1;
end;

function TS3TcPath.GetPrefix(const aRemoteName: string): string;
begin
  Result := ToS3Key(aRemoteName);
  if Result <> '' then
    Result := Result + '/'
end;

end.
