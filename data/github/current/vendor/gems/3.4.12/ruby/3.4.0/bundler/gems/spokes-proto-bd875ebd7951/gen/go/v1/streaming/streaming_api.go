package streaming

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewBatchBlobsRequest(reqCtx *types.RequestContext, repository *types.Repository, oids []*types.ObjectID, filters ...BlobFilterOpt) *BatchBlobsRequest {
	req := &BatchBlobsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Oids:           oids,
	}
	if len(filters) > 0 {
		req.Filters = &BlobFilter{}
		for _, filter := range filters {
			filter(req.Filters)
		}
	}
	return req
}

func (req *BatchBlobsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if filters := req.GetFilters(); filters != nil {
		if err := filters.Validate(); err != nil {
			return err
		}
	}

	if len(req.GetOids()) == 0 {
		return twirp.RequiredArgumentError("oids")
	}
	if len(req.GetOids()) > 1000 {
		return twirp.InvalidArgumentError("oids", "may contain up to 1000 items")
	}
	for _, oid := range req.GetOids() {
		if err := oid.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func (filters *BlobFilter) Validate() error {
	if filters == nil {
		return nil
	}

	if filters.GetPlainTextOnly() || filters.GetUtf8Only() || filters.GetMaxLineLength() > 0 {
		if filters.GetTruncateAt() > 0 {
			return twirp.InvalidArgumentError("filters.truncate_at", "cannot be used with content filters")
		}

		size := filters.GetMaxSize()
		if size <= 0 {
			return twirp.InvalidArgumentError("filters.max_size", "must be set if using content filters")
		}
		if size > 1024*1024 {
			return twirp.InvalidArgumentError("filters.max_size", "cannot exceed 1MiB")
		}
	}

	return nil
}
