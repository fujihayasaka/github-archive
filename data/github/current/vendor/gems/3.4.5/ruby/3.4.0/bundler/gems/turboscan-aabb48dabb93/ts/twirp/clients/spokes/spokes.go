// Package spokes contains Twirp clients for connecting to spokesd.
// See https://github.com/github/spokes-proto
package spokes

import (
	"context"
	"time"

	"github.com/github/go-twirp/v2/client/requestid"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	"github.com/github/go-stats"
	"github.com/github/spokes-proto/gen/go/v1/blobs"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"

	"github.com/github/turboscan/ts"
)

var ErrFileNotFound = errors.New("file not found")

type Spokes interface {
	GetFile(context.Context, ts.RepositoryEID, Filename, CommitOID) ([]byte, error)
}
type Filename []byte
type CommitOID string
type SpokesClient struct {
	twirpAddr string
	blobs     blobs.BlobsAPI

	sc stats.Client
}

func NewClient(addr, cert, clientKey, caChain string, s stats.Client) (Spokes, error) {
	c, err := newHttpClient(cert, clientKey, caChain)
	if err != nil {
		return nil, err
	}

	requestID := requestid.NewForwarder(c)

	return &SpokesClient{
		twirpAddr: addr,
		blobs:     blobs.NewBlobsAPIProtobufClient(addr, requestID),
		sc:        s,
	}, nil
}

func (client *SpokesClient) GetFile(ctx context.Context, repoId ts.RepositoryEID, filename Filename, commitoid CommitOID) ([]byte, error) {
	defer client.emitDistribution("GetFile")()

	req := blobs.NewGetBlobContentsRequestByObjectIDPath(
		spokes.NewRequestContext(spokes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST), // Fail fast in case of outages on Spokes. We will retry at the job level.
		spokes.NewRepository(uint64(repoId)),
		spokes.NewObjectID(string(commitoid)),
		spokes.NewPath([]byte(filename)),
	)
	resp, err := client.blobs.GetBlobContents(ctx, req)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) {
			if twerr.Code() == twirp.NotFound {
				appctx.Logger(ctx).WithError(err).Info("file not found via spokes", repoId.AsKVP(), kvp.String("file", string(filename)))
				return nil, ErrFileNotFound
			}
		}

		appctx.Logger(ctx).WithError(err).Error("error downloading file from spokes", repoId.AsKVP(), kvp.String("file", string(filename)))
		return nil, err
	}

	// 1MB hard limit on spokes server
	if resp.Truncated {
		appctx.Logger(ctx).Info("file downloaded from spokes is truncated", repoId.AsKVP(), kvp.String("file", string(filename)))
		return nil, ErrFileNotFound // Treat truncated files as not found. We need full files
	}

	return resp.Contents, nil
}

func (client *SpokesClient) emitDistribution(method string) func() {
	start := time.Now()
	return func() {
		client.sc.DistributionMs("spokes.request", stats.Tags{"method": method}, time.Since(start))
	}
}
