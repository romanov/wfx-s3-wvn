unit Wfx.Plugin.S3.tests;

{
  These tests never touch AWS and never read the developer's real
  ~/.aws/credentials - both are injected via TS3Plugin.CreateInjected.

  The Phase 1 group below pins the five P0 data-loss defects so they cannot
  come back:
    #1 RenMovFile ignored aMove, so a copy destroyed its own source
    #2 GetFile reported every failed download as a success
    #3 Delete/GetFile/PutFile used the last-browsed bucket, not the path's
    #4 ToS3Key corrupted keys containing the bucket name (see Path.tests)
    #5 MkDir reported failures as success
}

interface

uses
  System.SysUtils,
  System.IOUtils,
  WinApi.Windows,
  Data.Cloud.AmazonAPI,
  Wfx.Plugin.Intf,
  Wfx.Plugin.Consts,
  Wfx.Plugin.S3,
  Wfx.Plugin.S3.Client,
  Wfx.Plugin.S3.Fakes,
  DUnitX.TestFramework;

type
  [TestFixture]
  S3PluginFixture = class
  private
    FFake           : TFakeS3Client;
    FFakeRef        : IS3Client;   // keeps FFake alive for the fixture's lifetime
    FCredentialsPath: string;
  public
    SUT : TS3Plugin;

    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure PluginNameNotEmpty;

    [Test]
    procedure InitDoesNotRaise;

    [Test]
    procedure ListingRoot_AsksS3ForBuckets;

    { #1 - RenMovFile }

    [Test]
    procedure CopyWithinBucket_MustNotDeleteTheSource;

    [Test]
    procedure MoveWithinBucket_DeletesTheSource;

    [Test]
    procedure MoveAcrossBuckets_DeletesTheSource;

    [Test]
    procedure WhenCopyFails_SourceIsKeptAndErrorReported;

    { #2 - GetFile }

    [Test]
    procedure WhenDownloadFails_ReportsReadError;

    [Test]
    procedure WhenDownloadFails_NoPartialFileIsLeftBehind;

    { #3 - bucket comes from the path }

    [Test]
    procedure Delete_UsesBucketFromPath;

    [Test]
    procedure Delete_OnABucket_RemovesTheBucket;

    { #5 - MkDir }

    [Test]
    procedure MkDir_WhenCreateBucketFails_ReturnsFalse;

    [Test]
    procedure MkDir_InsideABucket_CreatesAFolderMarker;
  end;

implementation

const
  { Fabricated values - the fake never authenticates with them. All three keys
    must be present under [default] or ConnectToS3 drops into pmPickProfile. }
  CREDENTIALS_FIXTURE =
    '[default]'                                    + sLineBreak +
    'aws_access_key_id=EXAMPLE-ACCESS-KEY'         + sLineBreak +
    'aws_secret_access_key=EXAMPLE-SECRET-KEY'     + sLineBreak +
    'region=eu-west-1'                             + sLineBreak +
    '[other-profile]'                              + sLineBreak +
    'aws_access_key_id=EXAMPLE-ACCESS-KEY-2'       + sLineBreak +
    'aws_secret_access_key=EXAMPLE-SECRET-KEY-2'   + sLineBreak +
    'region=us-east-1'                             + sLineBreak;

procedure S3PluginFixture.Setup;
begin
  FFake    := TFakeS3Client.Create;
  FFakeRef := FFake;

  FCredentialsPath := TPath.Combine(TPath.GetTempPath, 'wfx-s3-tests.credentials');
  TFile.WriteAllText(FCredentialsPath, CREDENTIALS_FIXTURE);

  var LClient := FFakeRef;
  SUT := TS3Plugin.CreateInjected(
    function(const aConnectionInfo: TAmazonConnectionInfo): IS3Client
    begin
      Result := LClient;
    end,
    FCredentialsPath);
end;

procedure S3PluginFixture.TearDown;
begin
  // SUT is held as an object reference, never as IWfxPlugin: TWFXPlugin descends
  // from TInterfacedObject, so taking an interface reference here would refcount
  // it away early and double-free on Free.
  SUT.Free;
  SUT := nil;

  FFakeRef := nil;
  FFake    := nil;

  if TFile.Exists(FCredentialsPath) then
    TFile.Delete(FCredentialsPath);
end;

procedure S3PluginFixture.PluginNameNotEmpty;
begin
  Assert.IsNotEmpty(SUT.GetPluginName);
end;

procedure S3PluginFixture.InitDoesNotRaise;
begin
  Assert.WillNotRaiseAny( SUT.Init );
end;

procedure S3PluginFixture.ListingRoot_AsksS3ForBuckets;
begin
  // A bucket name with no '=' keeps FindFirstFile out of ISO8601ToDateTime,
  // which is a separate (Phase 2) concern.
  FFake.BucketNames.Add('example-bucket');

  SUT.Init;

  var LFindData: TWin32FindData;
  SUT.FindFirstFile(LFindData, '\');

  // Reaching ListBuckets at all proves the injected credentials file was read:
  // had it not been, ConnectToS3 would have stayed in pmPickProfile and never
  // asked S3 for anything.
  Assert.IsTrue(FFake.Called('ListBuckets'),
    'Expected the plugin to list buckets. ' + FFake.CallLog);
end;

{ #1 - RenMovFile }

procedure S3PluginFixture.CopyWithinBucket_MustNotDeleteTheSource;
begin
  SUT.Init;

  const LResult = SUT.RenMovFile('\files\a.txt', '\files\c.txt',
                                 False {aMove}, False {aOverWrite}, nil);

  Assert.AreEqual(FS_FILE_OK, LResult);
  Assert.IsTrue(FFake.Called('CopyObject|files|c.txt|files|a.txt'),
    'Expected the object to be copied. ' + FFake.CallLog);
  Assert.IsFalse(FFake.Called('DeleteObject|files|a.txt'),
    'RenMovFile deleted the source object even though aMove was False. ' + FFake.CallLog);
end;

procedure S3PluginFixture.MoveWithinBucket_DeletesTheSource;
begin
  SUT.Init;

  const LResult = SUT.RenMovFile('\files\a.txt', '\files\c.txt',
                                 True {aMove}, False, nil);

  Assert.AreEqual(FS_FILE_OK, LResult);
  Assert.IsTrue(FFake.Called('CopyObject|files|c.txt|files|a.txt'), FFake.CallLog);
  Assert.IsTrue(FFake.Called('DeleteObject|files|a.txt'),
    'A move must remove the source object. ' + FFake.CallLog);
end;

procedure S3PluginFixture.MoveAcrossBuckets_DeletesTheSource;
begin
  SUT.Init;

  // Previously the delete was gated on source and target buckets matching, so
  // a cross-bucket move silently left the source behind - it became a copy.
  const LResult = SUT.RenMovFile('\alpha\a.txt', '\beta\a.txt',
                                 True {aMove}, False, nil);

  Assert.AreEqual(FS_FILE_OK, LResult);
  Assert.IsTrue(FFake.Called('CopyObject|beta|a.txt|alpha|a.txt'), FFake.CallLog);
  Assert.IsTrue(FFake.Called('DeleteObject|alpha|a.txt'),
    'A cross-bucket move must remove the source object. ' + FFake.CallLog);
end;

procedure S3PluginFixture.WhenCopyFails_SourceIsKeptAndErrorReported;
begin
  SUT.Init;
  FFake.ResultCopyObject := False;

  const LResult = SUT.RenMovFile('\files\a.txt', '\files\c.txt',
                                 True {aMove}, False, nil);

  Assert.AreEqual(FS_FILE_WRITEERROR, LResult,
    'A failed copy must be reported, not swallowed.');
  Assert.IsFalse(FFake.Called('DeleteObject|files|a.txt'),
    'The source must survive a failed copy. ' + FFake.CallLog);
end;

{ #2 - GetFile }

procedure S3PluginFixture.WhenDownloadFails_ReportsReadError;
begin
  SUT.Init;
  FFake.ResultGetObject := False;

  const LLocal = TPath.Combine(TPath.GetTempPath, 'wfx-s3-download.tmp');
  try
    const LResult = SUT.GetFile('\files\a.txt', LLocal);
    Assert.AreEqual(FS_FILE_READERROR, LResult,
      'A failed download must not be reported as FS_FILE_OK.');
  finally
    if TFile.Exists(LLocal) then
      TFile.Delete(LLocal);
  end;
end;

procedure S3PluginFixture.WhenDownloadFails_NoPartialFileIsLeftBehind;
begin
  SUT.Init;
  FFake.ResultGetObject := False;

  const LLocal = TPath.Combine(TPath.GetTempPath, 'wfx-s3-download.tmp');
  try
    SUT.GetFile('\files\a.txt', LLocal);
    Assert.IsFalse(TFile.Exists(LLocal),
      'A failed download must not leave an empty file behind.');
  finally
    if TFile.Exists(LLocal) then
      TFile.Delete(LLocal);
  end;
end;

{ #3 - bucket comes from the path }

procedure S3PluginFixture.Delete_UsesBucketFromPath;
begin
  SUT.Init;

  // The bucket must be read off the path being deleted. The old code used a
  // field holding whichever bucket was browsed last, so this deleted from the
  // wrong bucket whenever the two differed.
  SUT.Delete('\archive\2024\report.csv');

  Assert.IsTrue(FFake.Called('DeleteObject|archive|2024/report.csv'),
    'Expected the delete to target the bucket named in the path. ' + FFake.CallLog);
end;

procedure S3PluginFixture.Delete_OnABucket_RemovesTheBucket;
begin
  SUT.Init;

  SUT.Delete('\archive\');

  Assert.IsTrue(FFake.Called('DeleteBucket|archive'),
    'A single-segment path is a bucket and must be removed as one. ' + FFake.CallLog);
end;

{ #5 - MkDir }

procedure S3PluginFixture.MkDir_WhenCreateBucketFails_ReturnsFalse;
begin
  SUT.Init;
  FFake.ResultCreateBucket := False;

  Assert.IsFalse(SUT.MkDir('\new-bucket'),
    'MkDir used to end in Exit(True), hiding the failure.');
  Assert.IsTrue(FFake.Called('CreateBucket|new-bucket'), FFake.CallLog);
end;

procedure S3PluginFixture.MkDir_InsideABucket_CreatesAFolderMarker;
begin
  SUT.Init;

  Assert.IsTrue(SUT.MkDir('\files\reports'));
  Assert.IsTrue(FFake.Called('UploadObject|files|reports/|0'),
    'Expected an empty object acting as a folder marker. ' + FFake.CallLog);
end;

initialization
  TDUnitX.RegisterTestFixture(S3PluginFixture);

end.
