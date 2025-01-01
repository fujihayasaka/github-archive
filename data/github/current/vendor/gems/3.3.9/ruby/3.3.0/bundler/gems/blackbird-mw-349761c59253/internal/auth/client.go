package auth

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/go-github/github"
	"github.com/pkg/errors"
	"golang.org/x/net/context"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
)

// AuthorizationClient defines an interface for getting accessible_repo_ids for
// an actor.
type AuthorizationClient interface {
	GetAccessibleResources(ctx context.Context, req BuildActorRequest) (*AccessibleResourcesResponse, error)
	GetAccessibleResourcesV2(ctx context.Context, req BuildActorRequest) (*entities.AccessibleResources, int, error)
}

// BuildActorRequest hold identifying information about an actor, used to fetch
// and cache authN information.
type BuildActorRequest struct {
	ActorID         uint32
	SessionID       string
	AccessToken     string
	AccessTokenKind string
	RequestIPAddr   string
	CacheTTL        time.Duration
}

// Mockzd is an AuthorizationClient suitable for testing. It holds a static map
// of accessible_repos keyed by actor_id.
type Mockzd struct {
	RepoIDs                   map[int64][]int64
	AuthorizedOrganizationIDs []int64
	AccessibleOrgIDs          []int64
	ProtectedOrganizationIDs  []int64
}

func NewMockzd(actorID int64, repoIDs []int64) *Mockzd {
	return &Mockzd{RepoIDs: map[int64][]int64{actorID: repoIDs}}
}

func (a Mockzd) GetAccessibleResources(ctx context.Context, req BuildActorRequest) (*AccessibleResourcesResponse, error) {
	return &AccessibleResourcesResponse{
		AccessibleRepositoryIDs:   a.RepoIDs[int64(req.ActorID)],
		AuthorizedOrganizationIDs: a.AuthorizedOrganizationIDs,
		ProtectedOrganizationIDs:  a.ProtectedOrganizationIDs,
	}, nil
}

func (a Mockzd) GetAccessibleResourcesV2(ctx context.Context, req BuildActorRequest) (*entities.AccessibleResources, int, error) {
	return &entities.AccessibleResources{
		AccessiblePrivateRepoIds: []uint64{1, 2, 3},
		AccessibleOwnerIds:       []uint64{1, 2, 3},
		ProtectedOrganizationIds: []uint64{1, 2, 3},
	}, http.StatusOK, nil
}

type FailingAuthClient struct {
	Error error
}

func (a FailingAuthClient) GetAccessibleResources(ctx context.Context, req BuildActorRequest) (*AccessibleResourcesResponse, error) {
	return nil, a.Error
}

func (a FailingAuthClient) GetAccessibleResourcesV2(ctx context.Context, req BuildActorRequest) (*entities.AccessibleResources, int, error) {
	return nil, http.StatusInternalServerError, a.Error
}

// BlackbirdInternalAPIClient uses the custom internal blackbird API for fetching
// accessible repositories.
type BlackbirdInternalAPIClient struct {
	baseURL              string
	accessibleRepoIDsURL string
	hmacSecret           string
	githubClient         *github.Client
}

func NewBlackbirdInternalAPIClient(httpClient *http.Client, baseURL string, hmacSecret string) *BlackbirdInternalAPIClient {
	if !strings.HasSuffix(baseURL, "/") {
		baseURL = baseURL + "/"
	}
	accessibleRepoIDsURL := fmt.Sprintf("%sinternal/blackbird/accessible_resources", baseURL)
	return &BlackbirdInternalAPIClient{baseURL, accessibleRepoIDsURL, hmacSecret, github.NewClient(httpClient)}
}

type AccessibleResourcesResponse struct {
	AccessibleRepositoryIDs     []int64 `json:"accessible_repository_ids"`
	AuthorizedOrganizationIDs   []int64 `json:"authorized_organization_ids"`
	ProtectedOrganizationIDs    []int64 `json:"protected_organization_ids"`
	OutsideCollaboratorOwnerIDs []int64 `json:"outside_collaborator_owner_ids"`
}

type AccessibleResourcesRequest struct {
	ActorID                     uint32 `json:"actor_id"`
	KeyPrefix                   string `json:"key_prefix"`
	RequestUserIP               string `json:"request_user_ip"`
	SessionID                   string `json:"session_id"`
	Token                       string `json:"token"`
	TokenKind                   string `json:"token_kind"`
	ForceNewAccessibleResources bool   `json:"force_new_accessible_resources"`
}

var ErrUnauthorized = errors.New("unauthorized, bad or expired token")

func (i *BlackbirdInternalAPIClient) GetAccessibleResources(ctx context.Context, req BuildActorRequest) (*AccessibleResourcesResponse, error) {
	if len(req.SessionID) == 0 {
		logging.Info(ctx, "empty session ID, must reauth!", kvp.Uint64("actor_id", uint64(req.ActorID)), kvp.String("ipaddr", req.RequestIPAddr))
		return nil, ErrUnauthorized
	}

	data, err := json.Marshal(&AccessibleResourcesRequest{
		ActorID:       req.ActorID,
		KeyPrefix:     keyPrefixV2(),
		RequestUserIP: req.RequestIPAddr,
		SessionID:     req.SessionID,
		Token:         req.AccessToken,
		TokenKind:     req.AccessTokenKind,
	})
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal json request")
	}

	request, err := http.NewRequestWithContext(ctx, "POST", i.accessibleRepoIDsURL, bytes.NewBuffer(data))
	if err != nil {
		return nil, errors.Wrap(err, "failed create request")
	}

	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())
	requestid.Forward(request)

	start := time.Now()
	defer func() {
		logging.Info(ctx, "GetAccessibleResources", kvp.Int64("accessible_resources_duration_ms", time.Since(start).Milliseconds()), kvp.Int64("actor_id", int64(req.ActorID)))
	}()
	var res AccessibleResourcesResponse
	response, err := i.githubClient.Do(ctx, request, &res)
	if err != nil {
		if response != nil {
			switch response.StatusCode {
			case http.StatusUnauthorized:
				logging.Info(ctx, "failed to get accessible_repo_ids", kvp.Uint64("actor_id", uint64(req.ActorID)), kvp.String("ipaddr", req.RequestIPAddr))
				return nil, ErrUnauthorized
			default:
				return nil, errors.Wrapf(err, "failed to get accessible_repo_ids for actor:%d ipaddr:%s", req.ActorID, req.RequestIPAddr)
			}
		}
	}
	return &res, nil
}

func (i *BlackbirdInternalAPIClient) GetAccessibleResourcesV2(ctx context.Context, req BuildActorRequest) (*entities.AccessibleResources, int, error) {
	if len(req.SessionID) == 0 {
		logging.Info(ctx, "empty session ID, must reauth!", kvp.Uint64("actor_id", uint64(req.ActorID)), kvp.String("ipaddr", req.RequestIPAddr))
		return nil, 0, ErrUnauthorized
	}

	data, err := json.Marshal(&AccessibleResourcesRequest{
		ActorID:                     req.ActorID,
		KeyPrefix:                   keyPrefixV2(),
		RequestUserIP:               req.RequestIPAddr,
		SessionID:                   req.SessionID,
		Token:                       req.AccessToken,
		TokenKind:                   req.AccessTokenKind,
		ForceNewAccessibleResources: true,
	})
	if err != nil {
		return nil, 0, errors.Wrap(err, "failed to marshal json request")
	}

	request, err := http.NewRequestWithContext(ctx, "POST", i.accessibleRepoIDsURL, bytes.NewBuffer(data))
	if err != nil {
		return nil, 0, errors.Wrap(err, "failed create request")
	}

	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())
	requestid.Forward(request)

	start := time.Now()
	defer func() {
		logging.Info(ctx, "GetAccessibleResources", kvp.Int64("accessible_resources_duration_ms", time.Since(start).Milliseconds()), kvp.Bool("force_new_accessible_resources", true), kvp.Int64("actor_id", int64(req.ActorID)))
	}()

	var res entities.AccessibleResources
	response, err := i.githubClient.Do(ctx, request, &res)
	if err != nil {
		if response != nil {
			switch response.StatusCode {
			case http.StatusUnauthorized:
				logging.Info(ctx, "failed to get accessible_repo_ids", kvp.Uint64("actor_id", uint64(req.ActorID)), kvp.String("ipaddr", req.RequestIPAddr))
				return nil, response.StatusCode, ErrUnauthorized
			default:
				return nil, response.StatusCode, errors.Wrapf(err, "failed to get accessible_repo_ids for actor:%d ipaddr:%s", req.ActorID, req.RequestIPAddr)
			}
		}
	}

	return &res, response.StatusCode, nil
}
