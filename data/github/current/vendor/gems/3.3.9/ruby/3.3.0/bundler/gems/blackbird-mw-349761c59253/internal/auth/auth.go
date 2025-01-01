package auth

import (
	"fmt"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
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

const (
	keyNamespace     = "blackbird"
	keyNamespaceV2   = "ar"
	namespaceVersion = "v2"
	redisActorKey    = "actor:v4"
)

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
func (c *Client) BuildActor(ctx context.Context, req BuildActorRequest) (*models.Actor, error) {
	r, err := c.authorizationClient.GetAccessibleResources(ctx, req)
	if err != nil {
		return nil, err
	}

	// accessible organizations = actor_id + authorized organization ids + outside collaborator owner ids
	accessibleOrganizationIDs := toSet(r.AuthorizedOrganizationIDs)
	accessibleOrganizationIDs[req.ActorID] = true
	for _, id := range r.OutsideCollaboratorOwnerIDs {
		accessibleOrganizationIDs[uint32(id)] = true
	}

	return &models.Actor{
		ID:                        req.ActorID,
		IP:                        req.RequestIPAddr,
		AccessiblePrivateRepoIDs:  toRepoIDSet(r.AccessibleRepositoryIDs),
		AccessibleOrganizationIDs: accessibleOrganizationIDs,
		AuthorizedOrganizationIDs: r.AuthorizedOrganizationIDs,
		ProtectedOrganizationIDs:  r.ProtectedOrganizationIDs,
		CacheExpiryTime:           time.Now().Add(req.CacheTTL).Unix(),
		SessionID:                 req.SessionID,
	}, nil
}

// BuildActorV2 returns the actor and associated list of accessible_repos from the
// cache, fetching new data from the AuthorizationClient if required.
// Uses new accessible resources fields to construct the actor, bubbling up
// any status codes that are returned from the AuthorizationClient.
func (c *Client) BuildActorV2(ctx context.Context, req BuildActorRequest) (*models.Actor, int, error) {
	r, statusCode, err := c.authorizationClient.GetAccessibleResourcesV2(ctx, req)
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
		logging.Error(ctx, "get actor from cache failed", kvp.String("key", key), kvp.Uint64("actor_id", uint64(actorID)), kvp.Err(err))
		return nil
	}
	statting.Distribution(ctx, "query.cache.actor_cache.get_size", float64(len(val)))

	var actor models.Actor
	if err := actor.Unmarshal(val); err != nil {
		logging.Error(ctx, "unmarshal actor failed", kvp.String("key", key), kvp.Uint64("actor_id", uint64(actorID)), kvp.Err(err))
		return nil
	}

	logging.Info(ctx, "GET actor from cache",
		kvp.String("key", key),
		kvp.Int("actor_id", int(actorID)),
		kvp.String("ip_addr", actorIP),
		kvp.Int("num_accessible_repos", len(actor.AccessiblePrivateRepoIDs)),
		kvp.Int("num_accessible_orgs", len(actor.AccessibleOrganizationIDs)),
		kvp.Int("num_authorized_orgs", len(actor.AuthorizedOrganizationIDs)),
		kvp.Int("num_protected_orgs", len(actor.ProtectedOrganizationIDs)),
		kvp.Int("session_id_length", len(actor.SessionID)),
	)
	return &actor
}

func (c *Client) GetActorV2(ctx context.Context, actorID uint32, actorIP string, sessionID string) *models.Actor {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "query.cache.actor_cache.get_time", time.Since(start), stats.Tags{"version": "v2"})
	}()

	key := actorKeyV2(actorID, sessionID)
	val, err := c.cache.Get(ctx, key)
	if err != nil {
		return nil
	}
	statting.Distribution(ctx, "query.cache.actor_cache.get_size", float64(len(val)), stats.Tags{"version": "v2"})

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
		kvp.String("version", "v2"),
		kvp.Int("actor_id", int(actorID)),
		kvp.String("ip_addr", actorIP),
		kvp.Int("num_accessible_repos", len(actor.AccessiblePrivateRepoIDs)),
		kvp.Int("num_accessible_orgs", len(actor.AccessibleOrganizationIDs)),
		kvp.Int("num_authorized_orgs", len(actor.AuthorizedOrganizationIDs)),
		kvp.Int("num_protected_orgs", len(actor.ProtectedOrganizationIDs)),
		kvp.Int("session_id_length", len(actor.SessionID)),
	)
	return &actor
}

func (c *Client) SetActor(ctx context.Context, actor *models.Actor, ttl time.Duration) error {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "query.cache.actor_cache.set_time", time.Since(start))
	}()

	key := actorKey(actor.ID, actor.SessionID)
	logging.Info(ctx, "SET actor in cache",
		kvp.String("key", key),
		kvp.Uint64("actor_id", uint64(actor.ID)),
		kvp.String("ip_addr", actor.IP),
		kvp.Int("num_accessible_repos", len(actor.AccessiblePrivateRepoIDs)),
		kvp.Int("num_accessible_orgs", len(actor.AccessibleOrganizationIDs)),
		kvp.Int("num_authorized_orgs", len(actor.AuthorizedOrganizationIDs)),
		kvp.Int("num_protected_orgs", len(actor.ProtectedOrganizationIDs)),
		kvp.Int("session_id_length", len(actor.SessionID)),
		kvp.Duration("ttl", ttl),
	)

	data, err := actor.Marshal()
	if err != nil {
		logging.Error(ctx, "marshal actor failed", kvp.Uint64("actor_id", uint64(actor.ID)), kvp.Err(err))
		return err
	}
	statting.Distribution(ctx, "query.cache.actor_cache.set_size", float64(len(data)))

	err = c.cache.Set(ctx, key, data, ttl)
	if err != nil {
		logging.Error(ctx, "set actor in cache failed", kvp.String("key", key), kvp.Uint64("actor_id", uint64(actor.ID)), kvp.Err(err))
		return err
	}

	return nil
}

func keyPrefix() string {
	return fmt.Sprintf("%s:%s", keyNamespace, namespaceVersion)
}

func keyPrefixV2() string {
	return fmt.Sprintf("%s:%s", keyNamespaceV2, namespaceVersion)
}

func actorKey(actorID uint32, sessionID string) string {
	return fmt.Sprintf("%s:%s:%d:%s", keyPrefix(), redisActorKey, actorID, sessionID)
}

func actorKeyV2(actorID uint32, sessionID string) string {
	return fmt.Sprintf("%s:%d:%s", keyPrefixV2(), actorID, sessionID)
}

func toUSet(ids []uint64) types.U32Set {
	m := make(types.U32Set, len(ids))
	for _, id := range ids {
		m[uint32(id)] = true
	}
	return m
}

func toSet(ids []int64) types.U32Set {
	m := make(types.U32Set, len(ids))
	for _, id := range ids {
		// TODO: Figure out if we need to move repo ids to u64
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
	var result []int64
	for _, id := range ids {
		result = append(result, int64(id))
	}
	return result
}
