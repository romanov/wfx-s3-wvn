unit Wfx.Plugin.S3.Path.tests;

{
  Contract tests for TS3TcPath.

  This table IS the specification of the path contract. It models what Total
  Commander actually passes: FsFindFirstW paths carry NO trailing backslash,
  except the root, which is '\'. So a folder arrives as '\bucket\folder'.

  The cases previously tagged [R] - the bucket-name-as-substring traps and
  IsBucket('\') - are fixed as of Phase 1 and now pass.
}

interface

uses
  Wfx.Plugin.S3.Path,
  DUnitX.TestFramework;

const
  /// DUnitX splits [TestCase] data on ',' and trailing empty values do not
  /// survive that reliably, so empty strings travel as a sentinel.
  EMPTY_MARKER = '(empty)';

type
  [TestFixture]
  S3PathFixture = class
  private
    FPath: TS3TcPath;
    function Decode(const aValue: string): string;
  public

    [Test]
    [TestCase('root',                        '\,(empty)')]
    [TestCase('bucket only',                 '\mybucket,mybucket')]
    [TestCase('bucket with trailing slash',  '\mybucket\,mybucket')]
    [TestCase('nested file',                 '\mybucket\folder\file.txt,mybucket')]
    [TestCase('key segment repeats bucket',  '\data\data\report.csv,data')]
    [TestCase('empty input',                 '(empty),(empty)')]
    procedure GetBucketName_ReturnsFirstSegment(const aRemoteName, aExpected: string);

    [Test]
    [TestCase('backslash is root',           '\,True')]
    [TestCase('empty is not root',           '(empty),False')]
    [TestCase('bucket is not root',          '\mybucket\,False')]
    procedure IsRoot_OnlyForSingleBackslash(const aRemoteName: string; const aExpected: Boolean);

    { IsBucket accepts a bucket with or without a trailing backslash.

      Phase 0 left this open because the source could not settle which form
      Total Commander passes to FsRemoveDirW, and the official WFX SDK header
      (ghisler/WFX-SDK, fsplugin.pas) carries no comment on path format.

      Phase 1 resolves it by not depending on the answer: within this plugin's
      namespace a single path segment IS a bucket, so both forms are accepted
      and bucket removal works either way. }
    [Test]
    [TestCase('bucket with trailing slash',  '\mybucket\,True')]
    [TestCase('bucket without slash',        '\mybucket,True')]
    [TestCase('root is not a bucket',        '\,False')]
    [TestCase('empty is not a bucket',       '(empty),False')]
    [TestCase('folder is not a bucket',      '\mybucket\folder\,False')]
    [TestCase('file is not a bucket',        '\mybucket\folder\file.txt,False')]
    procedure IsBucket_OnlyForSingleSegment(const aRemoteName: string; const aExpected: Boolean);

    { ToS3Key replaces the old StripAnyBucket / StripKnownBucket pair. Once both
      became "drop the leading segment" they were identical, so Phase 1 merged
      them. The bucket-name-as-substring rows are the regression guard for the
      Replace()-based implementation they replaced. }
    [Test]
    [TestCase('top level file',              '\data\report.csv,report.csv')]
    [TestCase('nested file',                 '\data\2024\report.csv,2024/report.csv')]
    [TestCase('bucket root',                 '\data\,(empty)')]
    [TestCase('bucket root no slash',        '\data,(empty)')]
    [TestCase('root',                        '\,(empty)')]
    [TestCase('key repeats bucket name',     '\data\data\report.csv,data/report.csv')]
    [TestCase('key starts with bucket',      '\data\data-report.csv,data-report.csv')]
    [TestCase('nested key w/ bucket',        '\data\2024\data-report.csv,2024/data-report.csv')]
    procedure ToS3Key_DropsLeadingSegmentOnly(const aRemoteName, aExpected: string);

    [Test]
    [TestCase('root',                        '\,(empty)')]
    [TestCase('bucket',                      '\mybucket,(empty)')]
    [TestCase('folder',                      '\mybucket\folder,folder/')]
    [TestCase('nested folder',               '\mybucket\a\b,a/b/')]
    [TestCase('folder repeats bucket',       '\data\data,data/')]
    [TestCase('folder starts w/ bucket',     '\data\data-2024,data-2024/')]
    procedure GetPrefix_AppendsSingleSlash(const aRemoteName, aExpected: string);
  end;

implementation

function S3PathFixture.Decode(const aValue: string): string;
begin
  if aValue = EMPTY_MARKER then
    Result := ''
  else
    Result := aValue;
end;

procedure S3PathFixture.GetBucketName_ReturnsFirstSegment(const aRemoteName, aExpected: string);
begin
  Assert.AreEqual(Decode(aExpected), FPath.GetBucketName(Decode(aRemoteName)));
end;

procedure S3PathFixture.IsRoot_OnlyForSingleBackslash(const aRemoteName: string; const aExpected: Boolean);
begin
  Assert.AreEqual(aExpected, FPath.IsRoot(Decode(aRemoteName)));
end;

procedure S3PathFixture.IsBucket_OnlyForSingleSegment(const aRemoteName: string; const aExpected: Boolean);
begin
  Assert.AreEqual(aExpected, FPath.IsBucket(Decode(aRemoteName)));
end;

procedure S3PathFixture.ToS3Key_DropsLeadingSegmentOnly(const aRemoteName, aExpected: string);
begin
  Assert.AreEqual(Decode(aExpected), FPath.ToS3Key(Decode(aRemoteName)));
end;

procedure S3PathFixture.GetPrefix_AppendsSingleSlash(const aRemoteName, aExpected: string);
begin
  Assert.AreEqual(Decode(aExpected), FPath.GetPrefix(Decode(aRemoteName)));
end;

initialization
  TDUnitX.RegisterTestFixture(S3PathFixture);

end.
