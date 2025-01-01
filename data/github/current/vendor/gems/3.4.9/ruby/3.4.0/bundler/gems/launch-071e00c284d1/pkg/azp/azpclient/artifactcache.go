package azpclient

import (
	"context"
	"net/http"

	errs "github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type ArtifactCacheService struct {
	client *Client
	http   *httpclient.Client
}

func (acs *ArtifactCacheService) ListCaches(ctx context.Context, key, scope, sort, direction string, page, perPage int64) ([]*azp.CacheEntry, int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "artifactcache.listcaches"

	var resp azp.CacheEntryResponse
	err := acs.http.Do(
		ctx,
		opname,
		http.MethodGet,
		acs.client.url.getListCacheURL(key, scope, sort, direction, page, perPage),
		nil,
		&resp,
		acs.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, 0, tracing.RecordError(span, err)
	}
	return resp.ArtifactCaches, resp.TotalCount, nil
}

func (acs *ArtifactCacheService) DeleteCachesByKey(ctx context.Context, key, scope string) ([]*azp.CacheEntry, int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "artifactcache.deletecachesbykey"

	var resp azp.CacheEntryResponse
	err := acs.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		acs.client.url.getDeleteCachesByKeyURL(key, scope),
		nil,
		&resp,
		acs.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, 0, tracing.RecordError(span, errs.Wrap(err, "the delete caches by key request cannot be made"))
	}

	return resp.ArtifactCaches, resp.TotalCount, nil
}

func (acs *ArtifactCacheService) DeleteCacheByID(ctx context.Context, cacheID int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "artifactcache.deletecachebyid"

	err := acs.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		acs.client.url.getDeleteCacheByIDURL(cacheID),
		nil,
		nil,
		acs.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "the delete cache by id request cannot be made"))
	}

	return nil
}
