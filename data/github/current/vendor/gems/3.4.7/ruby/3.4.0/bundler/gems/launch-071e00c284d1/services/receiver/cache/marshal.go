package cache

import (
	"context"
	"encoding/json"

	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	actionscacheevent "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/graphqlid"
)

type cacheUsage struct {
	HostID           string `json:"HostId"`
	TotalSizeInBytes int64  `json:"TotalSizeInBytes"`
	TotalCachesCount int64  `json:"TotalCachesCount"`
}

func (s *Service) getCacheUsageFromJSONPayload(ctx context.Context, payload []byte) (*actionscacheevent.CacheUsage, error) {
	var cacheUsageData cacheUsage
	if err := json.Unmarshal(payload, &cacheUsageData); err != nil {
		return nil, err
	}

	resource, ok, err := s.db.GetByTenantName(ctx, cacheUsageData.HostID)
	if err != nil {
		return nil, errors.Wrapf(err, "unable to resolve host: %q", cacheUsageData.HostID)
	}

	if !ok {
		return nil, errors.Errorf("host not found: %q", cacheUsageData.HostID)
	}

	typename, _, err := graphqlid.Decode(resource.EntityID.String())
	if err != nil {
		return nil, errors.Wrapf(err, "unable to decode global id: %q", resource.EntityID)
	}

	if typename != types.GlobalIDRepositoryType {
		return nil, errors.Errorf("host is not a repository: %q", cacheUsageData.HostID)
	}

	actionCacheStatsEntry := &actionscacheevent.CacheUsage{
		GlobalId:                resource.EntityID.String(),
		ActiveCachesSizeInBytes: cacheUsageData.TotalSizeInBytes,
		ActiveCachesCount:       cacheUsageData.TotalCachesCount,
		CreatedAt:               timestamppb.Now(),
	}
	return actionCacheStatsEntry, nil
}
