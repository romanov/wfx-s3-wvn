unit Wfx.Plugin.S3.Path.tests;

{
  Phase 0 safety net for TS3TcPath.

  This table IS the specification of the path contract. It models what Total
  Commander actually passes: FsFindFirstW paths carry NO trailing backslash,
  except the root, which is '\'. So a folder arrives as '\bucket\folder'.

  Cases tagged [R] below assert the CORRECT behaviour and FAIL against the
  current implementation. Those 9 failures are Phase 1's acceptance criteria -
  they are expected. Any OTHER failure is a real problem.
}

interface

uses
  Wfx.Plugin.S3.Path,
  DUnitX.TestFramework;

const
  /// DUnitX splits [TestCase] data on ',' and trailing empty values do not
  /// survive that reliably, so empty strings travel as a sentinel.
  EMPTY_MARKER = '(empty)';

  /// Chosen because 'data' appears both as its own path segment and as a
  /// substring of sibling keys - exactly the shape the current Replace()-based
  /// implementation corrupts.
  TRAP_BUCKET = 'data';

type
  [TestFixture]
  S3PathFixture = class
  private
    function Decode(const aValue: string): string;
    function PathOf(const aBucketName: string): TS3TcPath;
  public

    [Test]
    [TestCase('root',                        '\,(empty)')]
    [TestCase('bucket only',                 '\mybucket,mybucket')]
    [TestCase('nested file',                 '\mybucket\folder\file.txt,mybucket')]
    [TestCase('key segment repeats bucket',  '\data\data\report.csv,data')]
    [TestCase('empty input',                 '(empty),(empty)')]
    procedure GetBucketName_ReturnsFirstSegment(const aRemoteName, aExpected: string);

    [Test]
    [TestCase('backslash is root',           '\,True')]
    [TestCase('empty is not root',           '(empty),False')]
    [TestCase('bucket is not root',          '\mybucket\,False')]
    procedure IsRoot_OnlyForSingleBackslash(const aRemoteName: string; const aExpected: Boolean);

    [Test]
    [TestCase('bucket with trailing slash',  '\mybucket\,True')]
    [TestCase('root is not a bucket [R]',    '\,False')]
    [TestCase('folder is not a bucket',      '\mybucket\folder\,False')]
    [TestCase('file is not a bucket',        '\mybucket\folder\file.txt,False')]
    procedure IsBucket_OnlyForSingleSegment(const aRemoteName: string; const aExpected: Boolean);

    // StripAnyBucket and StripKnownBucket are driven from ONE shared table.
    // Once Phase 1 makes both "drop the leading segment, convert \ to /", they
    // become identical and can be merged into a single ToS3Key(). Sharing the
    // table here makes that merge trivially verifiable.

    [Test]
    [TestCase('top level file',              '\data\report.csv,report.csv')]
    [TestCase('nested file',                 '\data\2024\report.csv,2024/report.csv')]
    [TestCase('bucket root',                 '\data\,(empty)')]
    [TestCase('root',                        '\,(empty)')]
    [TestCase('key repeats bucket name [R]', '\data\data\report.csv,data/report.csv')]
    [TestCase('key starts with bucket [R]',  '\data\data-report.csv,data-report.csv')]
    [TestCase('nested key w/ bucket [R]',    '\data\2024\data-report.csv,2024/data-report.csv')]
    procedure StripAnyBucket_DropsLeadingSegmentOnly(const aRemoteName, aExpected: string);

    [Test]
    [TestCase('top level file',              '\data\report.csv,report.csv')]
    [TestCase('nested file',                 '\data\2024\report.csv,2024/report.csv')]
    [TestCase('bucket root',                 '\data\,(empty)')]
    [TestCase('root',                        '\,(empty)')]
    [TestCase('key repeats bucket name [R]', '\data\data\report.csv,data/report.csv')]
    [TestCase('key starts with bucket [R]',  '\data\data-report.csv,data-report.csv')]
    [TestCase('nested key w/ bucket [R]',    '\data\2024\data-report.csv,2024/data-report.csv')]
    procedure StripKnownBucket_DropsLeadingSegmentOnly(const aRemoteName, aExpected: string);

    [Test]
    [TestCase('root',                        '\,(empty)')]
    [TestCase('bucket',                      '\mybucket,(empty)')]
    [TestCase('folder',                      '\mybucket\folder,folder/')]
    [TestCase('nested folder',               '\mybucket\a\b,a/b/')]
    [TestCase('folder repeats bucket [R]',   '\data\data,data/')]
    [TestCase('folder starts w/ bucket [R]', '\data\data-2024,data-2024/')]
    procedure GetPrefix_AppendsSingleSlash(const aRemoteName, aExpected: string);

    { Open question, deliberately not asserted.

      IsBucket only returns True when the name ends in '\'. If Total Commander
      passes '\mybucket' (no trailing slash) to FsRemoveDirW / FsDeleteFileW,
      then TS3Plugin.Delete takes the object branch and calls DeleteObject
      instead of DeleteBucket - removing a bucket would silently do nothing.

      This cannot be settled from the source. Already checked and ruled out:
      the official WFX SDK header (ghisler/WFX-SDK, fsplugin.pas) declares
      FsRemoveDirW(RemoteName: pwidechar) with no comment on path format.

      The answer is in the FS-Plugin writer's guide CHM (totalcmd.net/plugring,
      "fsplugin_guide"), which is a download rather than a web page. Read it,
      then delete this [Ignore] and assert the real answer. }
    [Test]
    [Ignore('Phase 0 open question: confirm what TC passes to FsRemoveDirW/FsDeleteFileW')]
    procedure IsBucket_BucketWithoutTrailingSlash;
  end;

implementation

function S3PathFixture.Decode(const aValue: string): string;
begin
  if aValue = EMPTY_MARKER then
    Result := ''
  else
    Result := aValue;
end;

function S3PathFixture.PathOf(const aBucketName: string): TS3TcPath;
begin
  Result := TS3TcPath.Create(aBucketName);
end;

procedure S3PathFixture.GetBucketName_ReturnsFirstSegment(const aRemoteName, aExpected: string);
begin
  Assert.AreEqual(Decode(aExpected), PathOf(TRAP_BUCKET).GetBucketName(Decode(aRemoteName)));
end;

procedure S3PathFixture.IsRoot_OnlyForSingleBackslash(const aRemoteName: string; const aExpected: Boolean);
begin
  Assert.AreEqual(aExpected, PathOf(TRAP_BUCKET).IsRoot(Decode(aRemoteName)));
end;

procedure S3PathFixture.IsBucket_OnlyForSingleSegment(const aRemoteName: string; const aExpected: Boolean);
begin
  Assert.AreEqual(aExpected, PathOf(TRAP_BUCKET).IsBucket(Decode(aRemoteName)));
end;

procedure S3PathFixture.StripAnyBucket_DropsLeadingSegmentOnly(const aRemoteName, aExpected: string);
begin
  // StripAnyBucket derives the bucket from the path itself, so the record's
  // BucketName is irrelevant here - it is set only to keep the table shared.
  Assert.AreEqual(Decode(aExpected), PathOf(TRAP_BUCKET).StripAnyBucket(Decode(aRemoteName)));
end;

procedure S3PathFixture.StripKnownBucket_DropsLeadingSegmentOnly(const aRemoteName, aExpected: string);
begin
  Assert.AreEqual(Decode(aExpected), PathOf(TRAP_BUCKET).StripKnownBucket(Decode(aRemoteName)));
end;

procedure S3PathFixture.GetPrefix_AppendsSingleSlash(const aRemoteName, aExpected: string);
begin
  Assert.AreEqual(Decode(aExpected), PathOf(TRAP_BUCKET).GetPrefix(Decode(aRemoteName)));
end;

procedure S3PathFixture.IsBucket_BucketWithoutTrailingSlash;
begin
  Assert.IsTrue(PathOf('mybucket').IsBucket('\mybucket'));
end;

initialization
  TDUnitX.RegisterTestFixture(S3PathFixture);

end.
