package authenticator

import (
	"context"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/broadcaster"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/validators"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tokens"
	"github.com/github/authnd/internal/common/tokens/fgpat"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-http/middleware/requestid"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"

	"github.com/twitchtv/twirp"
	tw "github.com/twitchtv/twirp"
)

const (
	// credentialTypeLabel represents the metric label used for defining the
	// credential type. The label is also used to store and retrieve the credential
	// type into a Twirp error's metadata.
	credentialTypeLabel         = "credential_type"
	responseCredentialTypeLabel = "response_credential_type"

	// alt label formatting for non-metrics so we can convert logging to semantic conventions without breaking alarming
	credentialTypeLoggingLabel = "gh.authnd.authenticator.credential.type"
)

// context key whose value is the hash of the hmac which was used for validating
// the incoming request to the server.
type validatingHMACKey struct{}

func WithValidatingHMAC(ctx context.Context, hash string) context.Context {
	return context.WithValue(ctx, validatingHMACKey{}, hash)
}

// NewAuthenticatorServer returns a new Authentication v0 TwirpServer for the given AuthStore.
func NewAuthenticatorServer(
	store store.Store,
	hooks *twirp.ServerHooks,
	isEnterpriseServer bool,
) pb.TwirpServer {
	return pb.NewAuthenticatorServer(NewAuthenticator(store, isEnterpriseServer), hooks)
}

// NewAuthenticator returns a new Authenticator for the given AuthStore.
func NewAuthenticator(
	store store.Store,
	isEnterpriseServer bool,
) pb.Authenticator {
	// We don't pass the logger or statter down since everything from here gets a logger/statter from the context.
	if isEnterpriseServer {
		return newEnterpriseAuthenticator(store)
	}
	return newAuthenticator(store)
}

type authenticatorStore interface {
	store.Mysql1Store
	store.ProgrammaticAccessTokensStore
	store.AuthenticationTokensStore
	store.ScopedIntegrationInstallationsStore
}

type enterpriseAuthenticatorStore interface {
	store.ProgrammaticAccessTokensStore
	store.UsersStore
}

func newAuthenticator(
	store authenticatorStore,
) pb.Authenticator {
	return &Authenticator{
		environment:        "dotcom",
		requestBroadcaster: broadcaster.NewBroadcaster(),
		login: &validators.LoginValidator{
			Store: store,
		},
		ssh: &validators.SSHPublicKeyValidator{
			Store: store,
		},
		oauth: &validators.OAuthValidator{
			Store: store,
		},
		sat: validators.NewSignedAuthTokenValidator(store),
		mint: &validators.MintTokenValidator{
			Store: store,
		},
		s2s: &validators.ServerToServerTokenValidator{
			Store: store,
		},
	}
}

func newEnterpriseAuthenticator(
	store enterpriseAuthenticatorStore,
) pb.Authenticator {
	return &Authenticator{
		environment:        "enterprise",
		requestBroadcaster: broadcaster.NewBroadcaster(),
		login:              &validators.UnsupportedValidator{},
		ssh:                &validators.UnsupportedValidator{},
		oauth:              &validators.UnsupportedValidator{},
		sat:                &validators.UnsupportedValidator{},
		s2s:                &validators.UnsupportedValidator{},
		mint: &validators.MintTokenValidator{
			Store: store,
		},
	}
}

// Authenticator satisfies the pb.Authenticator interface and implements the
// Twirp implementation of the Authnd Spec.
type Authenticator struct {
	environment        string
	requestBroadcaster *broadcaster.Broadcaster
	login              validators.LoginValidatorInterface
	ssh                validators.SSHPublicKeyValidatorInterface
	oauth              validators.OAuthValidatorInterface
	s2s                validators.ServerToServerTokenValidatorInterface
	sat                validators.SignedAuthTokenValidatorInterface
	mint               validators.MintTokenValidatorInterface
}

// Authenticate authenticates the AuthenticateRequest credentials.
func (a *Authenticator) Authenticate(ctx context.Context, req *pb.AuthenticateRequest) (*pb.AuthenticateResponse, error) {
	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "Authenticator.Authenticate")
	defer span.End()

	if req.GetCredentials() == nil {
		span.RecordError(tw.RequiredArgumentError("credentials"))
		return nil, tw.RequiredArgumentError("credentials")
	}
	creds := req.GetCredentials()
	credsType := pb.CredentialTypeName(creds)

	span.SetAttributes(attribute.String(credentialTypeLoggingLabel, credsType))
	// https://thehub.github.com/epd/engineering/dev-practicals/observability/language-guides/go/semconv-migration/#haystack-api-compatibility
	// `deployed_to` needs to break from semantic conventions to remain compatible with haystack
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String(credentialTypeLoggingLabel, credsType), kvp.String("deployed_to", a.environment))

	// Log a message at the start that includes the credential type, to help with diagnosing issues.
	diagnostics.Logger(ctx).Info("received authenticate request")

	attributes, err := a.collapsibleAuthenticate(ctx, creds)

	var resp *pb.AuthenticateResponse
	if err != nil {
		resp, err = failedAuthenticateResponse(err)
		if err != nil {
			// wrap non-twirp errors in InternalError
			_, ok := err.(tw.Error)
			if !ok {
				err = tw.InternalErrorWith(err)
			}
			diagnostics.LogError(ctx, creds, err)
			span.RecordError(err)
			return nil, err
		}
	} else {
		resp = successfulAuthenticateResponse(attributes)
	}

	diagnostics.LogDecision(ctx, creds, resp)

	tags := stats.Tags{
		"authenticate_response": resp.GetResult().String(),
		"credential_type":       credsType,
		"credential_issuer":     a.environment,
	}
	respCredType, foundCredentialType := models.GetAttributeValue(attributes, client.CredentialTypeAttribute)
	if foundCredentialType {
		responseCredentialType := respCredType.GetStringValue()
		if responseCredentialType == pb.ProgrammaticAccessTokenType {
			tags["credential_issuer"] = "authnd"
		}
		tags = tags.Merge(stats.Tags{
			responseCredentialTypeLabel: responseCredentialType,
		})
	}

	statter := diagnostics.Statter(ctx)
	statter.Counter("authenticate.count", tags, 1)
	statter.DistributionMs("authenticate.duration", tags, time.Since(startTime))
	return resp, nil
}

func (a *Authenticator) authenticate(ctx context.Context, creds *pb.Credentials) ([]*pb.Attribute, error) {
	ctx, span := tracing.ChildSpan(ctx, "Authenticator.authenticate")
	defer span.End()

	switch creds.GetKind().(type) {
	case *pb.Credentials_LoginPassword:
		loginPassword := creds.GetLoginPassword()
		return a.authenticateLoginPassword(ctx, loginPassword)
	case *pb.Credentials_SshPublicKey:
		key := creds.GetSshPublicKey()
		return a.authenticateSSHPublicKey(ctx, key)
	case *pb.Credentials_AccessToken:
		token := creds.GetAccessToken()
		return a.authenticateAccessToken(ctx, token)
	case *pb.Credentials_SignedAuthToken:
		token := creds.GetSignedAuthToken()
		return a.authenticateSignedAuthToken(ctx, token)
	default:
		return nil, errors.Errorf("unknown credential type: %T", creds.GetKind())
	}
}

func (a *Authenticator) collapsibleAuthenticate(ctx context.Context, creds *pb.Credentials) ([]*pb.Attribute, error) {
	statter := diagnostics.Statter(ctx)

	key, collapsible := a.collapsibleRequest(creds)
	if !collapsible {
		statter.Counter("authenticate.collapse.skip", nil, 1)
		return a.authenticate(ctx, creds)
	}

	tags := stats.Tags{"collapsed": "false"}
	start := time.Now()
	defer func(s time.Time) {
		statter.Counter("authenticate.collapse.complete", tags, 1)
		statter.DistributionMs("authenticate.collapsed.duration_ms", tags, time.Since(s))
	}(start)

	// use request ID as session ID prefix to enable stitching listeners and broadcaster more easily in Splunk
	session := a.requestBroadcaster.NewSession(key, requestid.GetGitHubRequestID(ctx))
	logger := diagnostics.Logger(ctx).WithFields(kvp.Stringer("listener_session", session))

	resultCh, ok := a.requestBroadcaster.TryBroadcast(ctx, session)
	if ok {
		logger.Info("broadcasting authentication results", kvp.Stringer("broadcaster_session", session))
		// we are the first to request this, so we need to do the work and broadcast results
		// to any requests which come in while we are working.
		attributes, err := a.authenticate(ctx, creds)

		// non-blocking send because resultCh is buffered
		resultCh <- broadcaster.Result{
			Data: attributes,
			Err:  err,
		}

		// finish this request
		return attributes, err
	}

	// we are not the first to request this, so we need to wait for the first request to finish
	listenCh, ok := a.requestBroadcaster.TryListen(ctx, session)
	if !ok {
		// the broadcast session closed before we were able to listen. this should be rare, so
		// we'll stat and fallback to normal authentication.
		statter.Counter("authenticate.collapse.broadcast_closed_on_listen", tags, 1)
		return a.authenticate(ctx, creds)
	}
	tags["collapsed"] = "true"

	// wait for the result to finish
	waitStart := time.Now()
	select {
	case result := <-listenCh:
		if result.Err != nil {
			if errors.Is(result.Err, broadcaster.ErrNoResult) {
				// broadcaster returned no result. fallback to normal authentication.
				statter.Counter("authenticate.collapse.broadcast_no_result", tags, 1)
				return a.authenticate(ctx, creds)
			}

			if errors.Is(result.Err, broadcaster.ErrCancelled) {
				// broadcaster returned no result due to context cancellation. fallback to normal authentication.
				statter.Counter("authenticate.collapse.broadcast_cancelled", tags, 1)
				return a.authenticate(ctx, creds)
			}

			statter.Counter("authenticate.collapse.broadcast_error", tags, 1)
			return nil, result.Err
		}

		statter.DistributionMs("authenticate.collapse.listener_wait_ms", tags, time.Since(waitStart))
		logger.Info("received broadcast results", kvp.String("broadcaster_session", result.BroadcasterID))
		return result.Data.([]*pb.Attribute), nil

	case <-ctx.Done():
		statter.Counter("authenticate.collapse.listen_cancelled", tags, 1)
		return nil, ctx.Err()
	}
}

func (a *Authenticator) collapsibleRequest(creds *pb.Credentials) (key string, ok bool) {
	switch creds.GetKind().(type) {
	case *pb.Credentials_AccessToken:
		// only legacy PATs are support for now.  this enables us to safely test request collapsing against our science experiments
		// without affecting the correctness of production traffic.
		access := creds.GetAccessToken()
		if client.IsAuthndToken(access.Token) {
			return "prat:" + tokens.Hash(access.Token), true
		}
		return "oauth_access:" + tokens.Hash(access.Token), true
	default:
		return "", false
	}
}

// authenticateLoginPassword authenticates the given login password credentials.
func (a *Authenticator) authenticateLoginPassword(ctx context.Context, creds *pb.LoginPassword) ([]*pb.Attribute, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "login_password_auth")

	ctx, span := tracing.ChildSpan(ctx, "Authenticator.authenticateLoginPassword")
	defer span.End()

	login := creds.GetLogin()
	if login == "" {
		return nil, tw.RequiredArgumentError("credentials.login_password.login")
	}

	password := creds.GetPassword()
	if password == "" {
		return nil, tw.RequiredArgumentError("credentials.login_password.password")
	}

	return a.login.ValidateLoginPassword(ctx, login, password)
}

// authenticateSSHPublicKey authenticates the given SSH public key.
func (a *Authenticator) authenticateSSHPublicKey(ctx context.Context, key *pb.SSHPublicKey) ([]*pb.Attribute, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "ssh_public_key_auth")

	ctx, span := tracing.ChildSpan(ctx, "Authenticator.authenticateSSHPublicKey")
	defer span.End()

	k := key.GetKey()
	if k == "" {
		return nil, tw.RequiredArgumentError("credentials.ssh_public_key.key")
	}

	return a.ssh.ValidatePublicKey(ctx, k)
}

// authenticateAccessToken authenticates the given access token.
func (a *Authenticator) authenticateAccessToken(ctx context.Context, token *pb.AccessToken) ([]*pb.Attribute, error) {
	ctx, span := tracing.ChildSpan(ctx, "Authenticator.authenticateAccessToken")
	defer span.End()

	plaintext := token.GetToken()
	if plaintext == "" {
		return nil, tw.RequiredArgumentError("credentials.access_token.token")
	}
	tokenType := tokens.GetTokenType(plaintext)

	ctx = diagnostics.WithLoggerFields(ctx,
		kvp.String("gh.authnd.authenticator.credential.prefix", tokens.Prefix(plaintext)),
		kvp.String("gh.authnd.authenticator.credential.token_last_eight", tokens.LastEight(plaintext)),
		kvp.Stringer("gh.authnd.authenticator.credential.token_type", tokenType),
	)
	diagnostics.Logger(ctx).Info("authenticating access token")

	switch tokens.GetTokenType(plaintext) {

	case tokens.FineGrainedPersonalAccessToken:
		parsed, err := fgpat.ParseToken(plaintext)
		if err != nil {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID}
		}
		return a.mint.ValidateToken(ctx, parsed)

	case tokens.LegacyPersonalAccessToken, tokens.OAuthAppToken, tokens.GitHubAppUserToServerToken:
		return a.oauth.ValidateOAuthAccessToken(ctx, plaintext)

	case tokens.GitHubAppServerToServerToken:
		return a.s2s.ValidateServerToServerToken(ctx, plaintext)
	}

	return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID}
}

// authenticateSignedAuthToken authenticates the given SAT token.
func (a *Authenticator) authenticateSignedAuthToken(ctx context.Context, token *pb.SignedAuthToken) ([]*pb.Attribute, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "signed_auth_token_auth")

	ctx, span := tracing.ChildSpan(ctx, "Authenticator.authenticateSignedAuthToken")
	defer span.End()

	scope := token.GetScope()
	if scope == "" {
		return nil, tw.RequiredArgumentError("credentials.signedAuthToken.scope")
	}

	tk := token.GetToken()
	if tk == "" {
		return nil, tw.RequiredArgumentError("credentials.signedAuthToken.token")
	}

	return a.sat.ValidateSignedAuthToken(ctx, tk, scope)
}

// successfulAuthenticateResponse returns a *pb.AuthenticateResponse with RESULT_STATUS and the supplied
// attributes.
func successfulAuthenticateResponse(attrs []*pb.Attribute) *pb.AuthenticateResponse {
	return &pb.AuthenticateResponse{
		Result:     pb.AuthenticateResponse_RESULT_SUCCESS,
		Attributes: attrs,
	}
}

// failedAuthenticateResponse normalises an error into a *pb.AuthenticateResponse with the appropriate
// RESULT_FAILED_* code. If no better code can be found then the generic RESULT_FAILED_GENERIC will be used.
func failedAuthenticateResponse(err error) (*pb.AuthenticateResponse, error) {
	if err == nil {
		// this is a programming error, we should never pass nil to failedAuthenticateResponse
		panic("failedAuthenticateResponse called with nil err")
	}

	// Use errors.As because it searches down the entire error hierarchy
	var modelError *models.AuthenticationFailure
	if errors.As(err, &modelError) {
		return &pb.AuthenticateResponse{
			Result: modelError.Code,
		}, nil
	}

	// unknown or unexpected error
	return nil, err
}
