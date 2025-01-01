package spokesd

import (
	"context"

	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/objects"
)

// ObjectsService is an implementation of ObjectsAPI
type ObjectsService interface {
	ResolveObject(context.Context, *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error)
	ResolveObjects(context.Context, *objects.ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error)
}

// BlobsService is an implementation of BlobsAPI
type BlobsService interface {
	GetBlobContents(context.Context, *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error)
}

// CommitsService is an implementation of CommitsAPI
type CommitsService interface {
	CheckCommitReachability(context.Context, *commits.CheckCommitReachabilityRequest) (*commits.CheckCommitReachabilityResponse, error)
}
