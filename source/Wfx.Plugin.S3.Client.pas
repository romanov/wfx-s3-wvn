unit Wfx.Plugin.S3.Client;

{
  Thin pass-through seam over TAmazonStorageService.

  It exists for one reason: so TS3Plugin can be exercised against a fake instead
  of live S3. Without it there is no way to assert things like "a copy did NOT
  delete the source object".

  Deliberately NOT an abstraction. Signatures mirror the RTL exactly, including
  defaults, so existing call sites compile unchanged and the swap stays a
  no-behaviour-change edit. Resist tidying them here - plugin-owned DTOs are
  Phase 5 work.

  NOTE: these signatures were derived from the 10 call sites in Wfx.Plugin.S3.pas.
  Verify them against Data.Cloud.AmazonAPI.pas in your Delphi install before
  trusting a clean compile.
}

interface

uses
  System.Classes,
  Data.Cloud.CloudAPI,
  Data.Cloud.AmazonAPI;

type
  IS3Client = interface
    ['{B7A1710B-DB89-4305-98A7-8C644F3E273B}']
    function ListBuckets(ResponseInfo: TCloudResponseInfo = nil): TStrings;

    function GetBucket(const BucketName: string; OptionalParams: TStrings;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): TAmazonBucketResult;

    function GetObject(const BucketName, ObjectName: string;
      OptionalParams: TAmazonGetObjectOptionals; ObjectStream: TStream;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;

    function UploadObject(const BucketName, ObjectName: string; Content: TArray<Byte>;
      ReducedRedundancy: Boolean = False; Metadata: TStrings = nil; Headers: TStrings = nil;
      ACL: TAmazonACLType = TAmazonACLType.amzbaPrivate;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;

    function DeleteObject(const BucketName, ObjectName: string;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;

    function DeleteBucket(const BucketName: string;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;

    function CreateBucket(const BucketName: string;
      BucketACL: TAmazonACLType = TAmazonACLType.amzbaPrivate;
      const BucketRegion: TAmazonRegion = '';
      ResponseInfo: TCloudResponseInfo = nil): Boolean;

    function CopyObject(const DestinationBucket, DestinationObjectName,
      SourceBucket, SourceObjectName: string; Headers: TStrings = nil;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;
  end;

  /// Mirrors the TPluginFactory pattern already used in Wfx.Plugin.intf.pas.
  TS3ClientFactory = reference to function(const aConnectionInfo: TAmazonConnectionInfo): IS3Client;

  /// Production implementation. Owns only the TAmazonStorageService it creates;
  /// the caller keeps ownership of the TAmazonConnectionInfo, exactly as before.
  TAmazonS3Client = class(TInterfacedObject, IS3Client)
  private
    FService: TAmazonStorageService;
  public
    constructor Create(const aConnectionInfo: TAmazonConnectionInfo);
    destructor Destroy; override;

    function ListBuckets(ResponseInfo: TCloudResponseInfo = nil): TStrings;

    function GetBucket(const BucketName: string; OptionalParams: TStrings;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): TAmazonBucketResult;

    function GetObject(const BucketName, ObjectName: string;
      OptionalParams: TAmazonGetObjectOptionals; ObjectStream: TStream;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;

    function UploadObject(const BucketName, ObjectName: string; Content: TArray<Byte>;
      ReducedRedundancy: Boolean = False; Metadata: TStrings = nil; Headers: TStrings = nil;
      ACL: TAmazonACLType = TAmazonACLType.amzbaPrivate;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;

    function DeleteObject(const BucketName, ObjectName: string;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;

    function DeleteBucket(const BucketName: string;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;

    function CreateBucket(const BucketName: string;
      BucketACL: TAmazonACLType = TAmazonACLType.amzbaPrivate;
      const BucketRegion: TAmazonRegion = '';
      ResponseInfo: TCloudResponseInfo = nil): Boolean;

    function CopyObject(const DestinationBucket, DestinationObjectName,
      SourceBucket, SourceObjectName: string; Headers: TStrings = nil;
      ResponseInfo: TCloudResponseInfo = nil;
      const BucketRegion: TAmazonRegion = ''): Boolean;
  end;

/// The factory TS3Plugin uses unless a test injects its own.
function DefaultS3ClientFactory: TS3ClientFactory;

implementation

function DefaultS3ClientFactory: TS3ClientFactory;
begin
  Result :=
    function(const aConnectionInfo: TAmazonConnectionInfo): IS3Client
    begin
      Result := TAmazonS3Client.Create(aConnectionInfo);
    end;
end;

{ TAmazonS3Client }

constructor TAmazonS3Client.Create(const aConnectionInfo: TAmazonConnectionInfo);
begin
  inherited Create;
  FService := TAmazonStorageService.Create(aConnectionInfo);
end;

destructor TAmazonS3Client.Destroy;
begin
  FService.Free;
  inherited;
end;

function TAmazonS3Client.ListBuckets(ResponseInfo: TCloudResponseInfo): TStrings;
begin
  Result := FService.ListBuckets(ResponseInfo);
end;

function TAmazonS3Client.GetBucket(const BucketName: string; OptionalParams: TStrings;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): TAmazonBucketResult;
begin
  Result := FService.GetBucket(BucketName, OptionalParams, ResponseInfo, BucketRegion);
end;

function TAmazonS3Client.GetObject(const BucketName, ObjectName: string;
  OptionalParams: TAmazonGetObjectOptionals; ObjectStream: TStream;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): Boolean;
begin
  Result := FService.GetObject(BucketName, ObjectName, OptionalParams, ObjectStream,
    ResponseInfo, BucketRegion);
end;

function TAmazonS3Client.UploadObject(const BucketName, ObjectName: string;
  Content: TArray<Byte>; ReducedRedundancy: Boolean; Metadata, Headers: TStrings;
  ACL: TAmazonACLType; ResponseInfo: TCloudResponseInfo;
  const BucketRegion: TAmazonRegion): Boolean;
begin
  Result := FService.UploadObject(BucketName, ObjectName, Content, ReducedRedundancy,
    Metadata, Headers, ACL, ResponseInfo, BucketRegion);
end;

function TAmazonS3Client.DeleteObject(const BucketName, ObjectName: string;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): Boolean;
begin
  Result := FService.DeleteObject(BucketName, ObjectName, ResponseInfo, BucketRegion);
end;

function TAmazonS3Client.DeleteBucket(const BucketName: string;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): Boolean;
begin
  Result := FService.DeleteBucket(BucketName, ResponseInfo, BucketRegion);
end;

function TAmazonS3Client.CreateBucket(const BucketName: string; BucketACL: TAmazonACLType;
  const BucketRegion: TAmazonRegion; ResponseInfo: TCloudResponseInfo): Boolean;
begin
  Result := FService.CreateBucket(BucketName, BucketACL, BucketRegion, ResponseInfo);
end;

function TAmazonS3Client.CopyObject(const DestinationBucket, DestinationObjectName,
  SourceBucket, SourceObjectName: string; Headers: TStrings;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): Boolean;
begin
  Result := FService.CopyObject(DestinationBucket, DestinationObjectName,
    SourceBucket, SourceObjectName, Headers, ResponseInfo, BucketRegion);
end;

end.
