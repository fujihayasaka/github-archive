package spokesd

import "github.com/github/spokes-proto/gen/go/v1/types"

type ObjectIdentifier struct {
	Path string
	Ref  string
	SHA  string
}

type ResolveObjectsRequest struct {
	RepositoryID         int64
	ActorID              int64
	ObjectIdentifierList []*ObjectIdentifier
	QualityOfService     types.RequestContext_QualityOfService
}

type GetBlobContentsBatchRequest struct {
	RepositoryID     int64
	ActorID          int64
	ObjectIDs        []string
	QualityOfService types.RequestContext_QualityOfService
}

type GetBlobContentsBatchResponse struct {
	RepositoryID     int64
	BlobContentsByID BlobContentsByID
}

type Blob []byte

type BlobContentsByID map[string]Blob
