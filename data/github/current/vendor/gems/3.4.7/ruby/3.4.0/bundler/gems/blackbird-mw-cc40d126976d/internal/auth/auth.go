package auth

import (
	"fmt"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"golang.org/x/net/context"
	"google.golang.org/protobuf/proto"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/types"
)

// Note: Updating accessibleResourcesPrefix also requires updating the equivalent prefix in Rust and Ruby.
// - Ruby: https://github.com/github/github/blob/1947a0114299b7b0f7f0a0a67d3e3d94b232a30a/packages/search/app/models/blackbird_search/redis.rb#L8
// - Rust: https://github.com/github/blackbird/blob/8d193a9b14871128c68dd93463eae6793c15a2ff/crates/auth/src/lib.rs#L202
const accessibleResourcesPrefix = "ar:v2"

// Client is an authorization client plus cache that allows fetching the list of
// accessible_repos for an actor.
type Client struct {
	cache               cache.Store
	store               db.Store
	authorizationClient AuthorizationClient
}

func NewClient(cache cache.Store, authorizationClient AuthorizationClient, store db.Store) *Client {
	return &Client{cache, store, authorizationClient}
}

// BuildActor returns the actor and associated list of accessible_repos from the
// cache, fetching new data from the AuthorizationClient if required.
// Uses new accessible resources fields to construct the actor, bubbling up
// any status codes that are returned from the AuthorizationClient.
func (c *Client) BuildActor(ctx context.Context, req BuildActorRequest) (*models.Actor, int, error) {
	r, statusCode, err := c.authorizationClient.GetAccessibleResources(ctx, req)
	if err != nil {
		return nil, statusCode, err
	}

	return &models.Actor{
		ID:                        req.ActorID,
		IP:                        req.RequestIPAddr,
		AccessiblePrivateRepoIDs:  toRepoIDSet(convertUint64SliceToInt64(r.AccessiblePrivateRepoIds)),
		AccessibleOrganizationIDs: toUSet(r.AccessibleOwnerIds),
		AuthorizedOrganizationIDs: convertUint64SliceToInt64(r.AuthorizedOrganizationIds),
		ProtectedOrganizationIDs:  convertUint64SliceToInt64(r.ProtectedOrganizationIds),
		CacheExpiryTime:           time.Now().Add(req.CacheTTL).Unix(),
		SessionID:                 req.SessionID,
	}, statusCode, nil
}

func (c *Client) GetActor(ctx context.Context, actorID uint32, actorIP string, sessionID string) *models.Actor {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "query.cache.actor_cache.get_time", time.Since(start))
	}()

	key := actorKey(actorID, sessionID)
	val, err := c.cache.Get(ctx, key)
	if err != nil {
		return nil
	}
	statting.Distribution(ctx, "query.cache.actor_cache.get_size", float64(len(val)))

	var ar entities.AccessibleResources
	err = proto.Unmarshal(val, &ar)
	if err != nil {
		logging.Error(ctx, "unmarshalling accessible resources failed", kvp.String("key", key), kvp.Uint64("actor_id", uint64(actorID)), kvp.Err(err))
		return nil
	}

	actor := models.Actor{
		ID:                        actorID,
		IP:                        actorIP,
		AccessiblePrivateRepoIDs:  toRepoIDSet(convertUint64SliceToInt64(ar.AccessiblePrivateRepoIds)),
		AccessibleOrganizationIDs: toUSet(ar.AccessibleOwnerIds),
		AuthorizedOrganizationIDs: convertUint64SliceToInt64(ar.AuthorizedOrganizationIds),
		ProtectedOrganizationIDs:  convertUint64SliceToInt64(ar.ProtectedOrganizationIds),
		SessionID:                 sessionID,
	}

	logging.Info(ctx, "GET actor from cache",
		kvp.String("key", key),
		kvp.Int("actor_id", int(actorID)),
		kvp.String("ip_addr", actorIP),
		kvp.Int("num_accessible_repos", len(actor.AccessiblePrivateRepoIDs)),
		kvp.Int("num_accessible_orgs", len(actor.AccessibleOrganizationIDs)),
		kvp.Int("num_authorized_orgs", len(actor.AuthorizedOrganizationIDs)),
		kvp.Int("num_protected_orgs", len(actor.ProtectedOrganizationIDs)),
		kvp.String("session_id", actor.SessionID),
		kvp.Int("session_id_length", len(actor.SessionID)),
	)
	return &actor
}

func actorKey(actorID uint32, sessionID string) string {
	return fmt.Sprintf("%s:%d:%s", accessibleResourcesPrefix, actorID, sessionID)
}

func toUSet(ids []uint64) types.U32Set {
	m := make(types.U32Set, len(ids))
	for _, id := range ids {
		m[uint32(id)] = true
	}
	return m
}

func toRepoIDSet(ids []int64) types.RepoIDSet {
	m := make(types.RepoIDSet, len(ids))
	for _, id := range ids {
		// TODO: Figure out if we need to move repo ids to u64
		m[types.RepoID(id)] = true
	}
	return m
}

func convertUint64SliceToInt64(ids []uint64) []int64 {
	result := make([]int64, len(ids))
	for idx, id := range ids {
		result[idx] = int64(id)
	}
	return result
}
