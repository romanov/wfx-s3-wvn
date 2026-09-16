unit Wfx.Plugin.S3.Fakes;

{
  In-memory IS3Client for tests. Records every call as 'Method|arg|arg|...' so a
  test can assert on what the plugin asked S3 to do - and, more importantly, on
  what it did NOT do. Nothing here touches the network.
}

interface

uses
  System.Classes,
  System.SysUtils,
  Data.Cloud.CloudAPI,
  Data.Cloud.AmazonAPI,
  Wfx.Plugin.S3.Client;

type
  TFakeS3Client = class(TInterfacedObject, IS3Client)
  private
    FCalls      : TStringList;
    FBucketNames: TStringList;
    procedure Track(const aCall: string);
  public
    { Canned return values, all True by default. }
    ResultGetObject   : Boolean;
    ResultUploadObject: Boolean;
    ResultDeleteObject: Boolean;
    ResultDeleteBucket: Boolean;
    ResultCreateBucket: Boolean;
    ResultCopyObject  : Boolean;

    /// Handed back verbatim by GetBucket. Nil by default; the test owns it.
    NextBucketResult: TAmazonBucketResult;

    constructor Create;
    destructor Destroy; override;

    /// Recorded calls, in order.
    property Calls: TStringList read FCalls;
    /// What ListBuckets should report. The test populates this.
    property BucketNames: TStringList read FBucketNames;

    function Called(const aCall: string): Boolean;
    /// Readable dump for assertion messages.
    function CallLog: string;

    { IS3Client }
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

implementation

{ TFakeS3Client }

constructor TFakeS3Client.Create;
begin
  inherited Create;
  FCalls       := TStringList.Create;
  FBucketNames := TStringList.Create;

  ResultGetObject    := True;
  ResultUploadObject := True;
  ResultDeleteObject := True;
  ResultDeleteBucket := True;
  ResultCreateBucket := True;
  ResultCopyObject   := True;
end;

destructor TFakeS3Client.Destroy;
begin
  FBucketNames.Free;
  FCalls.Free;
  inherited;
end;

procedure TFakeS3Client.Track(const aCall: string);
begin
  FCalls.Add(aCall);
end;

function TFakeS3Client.Called(const aCall: string): Boolean;
begin
  Result := FCalls.IndexOf(aCall) >= 0;
end;

function TFakeS3Client.CallLog: string;
begin
  if FCalls.Count = 0 then
    Result := 'No S3 calls were recorded.'
  else
    Result := 'Recorded S3 calls: ' + FCalls.CommaText;
end;

function TFakeS3Client.ListBuckets(ResponseInfo: TCloudResponseInfo): TStrings;
begin
  Track('ListBuckets');
  // The RTL hands ownership of this list to the caller, so the fake does too.
  Result := TStringList.Create;
  Result.Assign(FBucketNames);
end;

function TFakeS3Client.GetBucket(const BucketName: string; OptionalParams: TStrings;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): TAmazonBucketResult;
begin
  var LPrefix := '';
  if Assigned(OptionalParams) then
    LPrefix := OptionalParams.Values['prefix'];

  Track(Format('GetBucket|%s|%s', [BucketName, LPrefix]));
  Result := NextBucketResult;
end;

function TFakeS3Client.GetObject(const BucketName, ObjectName: string;
  OptionalParams: TAmazonGetObjectOptionals; ObjectStream: TStream;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): Boolean;
begin
  Track(Format('GetObject|%s|%s', [BucketName, ObjectName]));
  Result := ResultGetObject;
end;

function TFakeS3Client.UploadObject(const BucketName, ObjectName: string;
  Content: TArray<Byte>; ReducedRedundancy: Boolean; Metadata, Headers: TStrings;
  ACL: TAmazonACLType; ResponseInfo: TCloudResponseInfo;
  const BucketRegion: TAmazonRegion): Boolean;
begin
  Track(Format('UploadObject|%s|%s|%d', [BucketName, ObjectName, Length(Content)]));
  Result := ResultUploadObject;
end;

function TFakeS3Client.DeleteObject(const BucketName, ObjectName: string;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): Boolean;
begin
  Track(Format('DeleteObject|%s|%s', [BucketName, ObjectName]));
  Result := ResultDeleteObject;
end;

function TFakeS3Client.DeleteBucket(const BucketName: string;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): Boolean;
begin
  Track(Format('DeleteBucket|%s', [BucketName]));
  Result := ResultDeleteBucket;
end;

function TFakeS3Client.CreateBucket(const BucketName: string; BucketACL: TAmazonACLType;
  const BucketRegion: TAmazonRegion; ResponseInfo: TCloudResponseInfo): Boolean;
begin
  Track(Format('CreateBucket|%s', [BucketName]));
  Result := ResultCreateBucket;
end;

function TFakeS3Client.CopyObject(const DestinationBucket, DestinationObjectName,
  SourceBucket, SourceObjectName: string; Headers: TStrings;
  ResponseInfo: TCloudResponseInfo; const BucketRegion: TAmazonRegion): Boolean;
begin
  Track(Format('CopyObject|%s|%s|%s|%s',
    [DestinationBucket, DestinationObjectName, SourceBucket, SourceObjectName]));
  Result := ResultCopyObject;
end;

end.
