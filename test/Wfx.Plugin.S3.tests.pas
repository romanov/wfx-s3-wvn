unit Wfx.Plugin.S3.tests;

{
  These tests never touch AWS and never read the developer's real
  ~/.aws/credentials - both are injected via TS3Plugin.CreateInjected.

  CopyWithinBucket_MustNotDeleteTheSource asserts the CORRECT behaviour and
  FAILS today. That failure is bug #1 from the scan (RenMovFile ignores aMove)
  and is Phase 1's headline acceptance criterion.
}

interface

uses
  System.SysUtils,
  System.IOUtils,
  WinApi.Windows,
  Data.Cloud.AmazonAPI,
  Wfx.Plugin.Intf,
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

    [Test]
    procedure CopyWithinBucket_MustNotDeleteTheSource;
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

procedure S3PluginFixture.CopyWithinBucket_MustNotDeleteTheSource;
begin
  SUT.Init;

  SUT.RenMovFile('\files\a.txt', '\files\c.txt', False {aMove}, False {aOverWrite}, nil);

  Assert.IsTrue(FFake.Called('CopyObject|files|c.txt|files|a.txt'),
    'Expected the object to be copied. ' + FFake.CallLog);

  Assert.IsFalse(FFake.Called('DeleteObject|files|a.txt'),
    'RenMovFile deleted the source object even though aMove was False. ' + FFake.CallLog);
end;

initialization
  TDUnitX.RegisterTestFixture(S3PluginFixture);

end.
