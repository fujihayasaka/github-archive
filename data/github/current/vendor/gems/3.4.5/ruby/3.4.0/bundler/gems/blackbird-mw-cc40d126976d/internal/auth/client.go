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
	GetAccessibleResources(ctx context.Context, req BuildActorRequest) (*entities.AccessibleResources, int, error)
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
	RepoIDs                   map[int64][]uint64
	AuthorizedOrganizationIDs []uint64
	AccessibleOwnerIDs        []uint64
	ProtectedOrganizationIDs  []uint64
}

func NewMockzd(actorID int64, repoIDs []uint64) *Mockzd {
	return &Mockzd{RepoIDs: map[int64][]uint64{actorID: repoIDs}}
}

func (a Mockzd) GetAccessibleResources(ctx context.Context, req BuildActorRequest) (*entities.AccessibleResources, int, error) {
	return &entities.AccessibleResources{
		AccessiblePrivateRepoIds: a.RepoIDs[int64(req.ActorID)],
		AccessibleOwnerIds:       a.AccessibleOwnerIDs,
		ProtectedOrganizationIds: a.ProtectedOrganizationIDs,
	}, http.StatusOK, nil
}

type FailingAuthClient struct {
	Error error
}

func (a FailingAuthClient) GetAccessibleResources(ctx context.Context, req BuildActorRequest) (*entities.AccessibleResources, int, error) {
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

func (i *BlackbirdInternalAPIClient) GetAccessibleResources(ctx context.Context, req BuildActorRequest) (*entities.AccessibleResources, int, error) {
	if len(req.SessionID) == 0 {
		logging.Info(ctx, "empty session ID, must reauth!", kvp.Uint64("actor_id", uint64(req.ActorID)), kvp.String("ipaddr", req.RequestIPAddr))
		return nil, 0, ErrUnauthorized
	}

	data, err := json.Marshal(&AccessibleResourcesRequest{
		ActorID:                     req.ActorID,
		KeyPrefix:                   accessibleResourcesPrefix,
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
		// The go-github client package automatically converts 202 Accepted
		// responses into an error. We specially handle that case as we do not
		// regard a 202 Accepted response as an error. The caller expects a valid
		// `entities.AccessibleResources` object in this case (even if it is empty).
		if errors.Is(err, &github.AcceptedError{}) {
			return &res, response.StatusCode, nil
		}

		if response != nil {
			switch response.StatusCode {
			case http.StatusUnauthorized:
				logging.Info(ctx, "failed to get accessible_repo_ids", kvp.Uint64("actor_id", uint64(req.ActorID)), kvp.String("ipaddr", req.RequestIPAddr))
				return nil, response.StatusCode, ErrUnauthorized
			default:
				return nil, response.StatusCode, errors.Wrapf(err, "failed to get accessible_repo_ids for actor:%d ipaddr:%s", req.ActorID, req.RequestIPAddr)
			}
		}

		return nil, http.StatusInternalServerError, errors.Wrapf(err, "failed to get accessible_repo_ids for actor:%d ipaddr:%s", req.ActorID, req.RequestIPAddr)
	}

	return &res, response.StatusCode, nil
}
