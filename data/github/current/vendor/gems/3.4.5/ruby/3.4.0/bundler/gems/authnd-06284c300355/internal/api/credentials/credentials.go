package credentials

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/authnd/client"
	"github.com/github/authnd/internal/api/middleware"
	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/sat"
	"github.com/github/authnd/internal/api/tenancy"
	"github.com/github/authnd/internal/api/utils"
	"github.com/github/authnd/internal/api/validators"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/publisher"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tokens/fgpat"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-ctxutil"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	schema "github.com/github/authnd/internal/common/publisher/hydro/schemas/authnd/v0"
	"github.com/twitchtv/twirp"
)

const (
	// MaxVerifyCredentialBatchSize the maximum number of credentials allowed in a batch verify request
	MaxVerifyCredentialBatchSize = 100
	// MaxRevokeBatchSize the maximum number of credentials allowed in a batch revoke request
	MaxRevokeBatchSize = 100
	// RevokeReasonCredentialExposed is the reason used by Secret Scanning when revoking a credential
	RevokeReasonCredentialExposed = "CredentialExposed"
)

// A CredentialManager implements the CredentialManager protobuf service.
type CredentialManager struct {
	store     CredentialManagerStore
	publisher publisher.PratEventPublisher
	mint      *validators.MintTokenValidator
}

type basePromotedAttributes struct {
	ActorID   uint64
	ActorType string
}

type PrATPromotedAttributes struct {
	AccessID uint64
	basePromotedAttributes
}

type CredentialManagerStore interface {
	store.ProgrammaticAccessTokensStore
	store.UsersStore
}

// NewCredentialManagerServer creates a new CredentialManager and uses the provided Twirp ServerHooks to create a TwirpServer that can host it.
func NewCredentialManagerServer(store CredentialManagerStore, publisher publisher.PratEventPublisher, hooks *twirp.ServerHooks) pb.TwirpServer {
	manager := &CredentialManager{
		store:     store,
		publisher: publisher,
		mint: &validators.MintTokenValidator{
			Store: store,
		},
	}
	return pb.NewCredentialManagerServer(manager, hooks)
}

// IssueToken issues a new token credential.
func (c *CredentialManager) IssueToken(ctx context.Context, req *pb.IssueTokenRequest) (*pb.IssueTokenResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "issue_mint_token")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "CredentialManager.IssueToken")
	defer span.End()

	span.SetAttributes(attribute.String("gh.authnd.credentials.request.token.type", req.Type))
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.credentials.credential.token.type", req.Type))

	diagnostics.Logger(ctx).Info("received IssueToken request")
	var resp *pb.IssueTokenResponse
	var err error

	switch req.Type {
	case pb.ProgrammaticAccessTokenType:
		resp, err = c.issueProgrammaticAccessToken(ctx, req)
	default:
		resp = &pb.IssueTokenResponse{
			Result: pb.IssueTokenResponse_RESULT_UNSUPPORTED_TOKEN_TYPE,
			Error:  fmt.Sprintf("specified token type '%s' is not supported", req.Type),
		}
	}

	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("token issue error", kvp.String("result", resp.GetResult().String()))
	}

	tags := stats.Tags{"issue_response": resp.GetResult().String(), "token_type": req.Type}
	statter := diagnostics.Statter(ctx)
	statter.Counter("issue_token.count", tags, 1)
	statter.DistributionMs("issue_token.duration", tags, time.Since(startTime))
	return resp, err
}

func (c *CredentialManager) issueProgrammaticAccessToken(ctx context.Context, req *pb.IssueTokenRequest) (*pb.IssueTokenResponse, error) {
	attrs, err := parsePrATAttributes(req.Attributes)
	if err != nil {
		return &pb.IssueTokenResponse{
			Result: pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES,
			Error:  err.Error(),
		}, nil
	}

	if attrs.AccessID == 0 {
		return &pb.IssueTokenResponse{
			Result: pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES,
			Error:  newMissingRequiredAttributeError(client.ProgrammaticAccessIDAttribute).Error(),
		}, nil
	}

	issuedAt := time.Now().UTC()

	// Generate a new token.
	header := fgpat.NewV1Header(fgpat.ProgrammaticAccessTokenType, uint32(attrs.ActorID))
	tok, err := fgpat.GenerateToken(fgpat.V1Prefix, header)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	// Hash the token
	hash := tok.Hash()

	// JSON-serialize the attributes
	serialized, err := apimodels.SerializeAttributes(req.Attributes)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	// Generate the token object
	m := &models.ProgrammaticAccessToken{
		HashedToken: []byte(hash),
		TokenSuffix: []byte(tok.GetSuffix()),
		AccessID:    attrs.AccessID,
		MintTokenCommon: &models.MintTokenCommon{
			ActorID:    attrs.ActorID,
			ActorType:  attrs.ActorType,
			IssuedAt:   issuedAt,
			Attributes: serialized,
		},
	}

	if req.ExpiresAtTime != nil {
		expiresAt := req.ExpiresAtTime.AsTime()
		m.ExpiresAt = models.NullMysqlDateTimeFromTime(expiresAt)
	}

	// if we are in a proxima environment, kickoff user validation in the background to
	// ensure they exist and that they are valid
	if tenancy.GetTenantContext(ctx) != nil {
		awaitUser, _ := utils.ValidateUserInBackground(ctx, func(innerContext context.Context) (*models.User, error) {
			return c.store.FindUserByID(innerContext, int64(attrs.ActorID))
		})
		// we immediately await the result since we can't really optimize
		// running anything else in parallel unless we wanted to be overly optimistic
		// with the insert and then rollback if the user doesn't exist
		user, err := awaitUser()
		if err != nil {
			if errors.Is(utils.UserValidationError_UserSuspended, err) {
				return &pb.IssueTokenResponse{
					Result: pb.IssueTokenResponse_RESULT_FAILED_USER_SUSPENDED,
				}, nil
			}
			return &pb.IssueTokenResponse{
				Result: pb.IssueTokenResponse_RESULT_FAILED_GENERIC,
				Error:  err.Error(),
			}, nil
		}
		if user == nil {
			return &pb.IssueTokenResponse{
				Result: pb.IssueTokenResponse_RESULT_FAILED_USER_UNKNOWN,
			}, nil
		}
	}

	err = c.store.InsertProgrammaticAccessToken(ctx, m)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	findToken := func(ctx context.Context) (*models.ProgrammaticAccessToken, error) {
		return m, nil
	}
	go c.emitProgrammaticAccessEvent(ctx, schema.ProgrammaticAccessEvent_ISSUED, "IssueProgrammaticAccessToken", findToken)

	// Return the response
	resp := &pb.IssueTokenResponse{
		Result:        pb.IssueTokenResponse_RESULT_SUCCESS,
		Token:         tok.Value,
		TokenId:       int64(m.ID),
		ExpiresAtTime: req.ExpiresAtTime,
	}

	return resp, nil
}

func (c *CredentialManager) IssueSignedAuthToken(ctx context.Context, req *pb.IssueSignedAuthTokenRequest) (*pb.IssueSignedAuthTokenResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "issue_signed_auth_token")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "CredentialManager.IssueSignedAuthToken")
	defer span.End()

	diagnostics.Logger(ctx).Info("received IssueSignedAuthToken request")
	resp := &pb.IssueSignedAuthTokenResponse{}
	err := validateAuthTokenRequest(req)
	if err != nil {
		return resp, err
	}

	// TODO(chriskirkland): make the user optional if the session is provided

	attrs := map[string]interface{}{}
	for _, attr := range req.Attributes {
		val, err := attr.Value.Unwrap()
		if err != nil {
			resp.Error = err.Error()
			return resp, err
		}
		attrs[attr.Id] = val
	}
	user, err := c.mint.Store.FindUserByID(ctx, int64(req.UserId))
	if err != nil {
		return resp, err
	}

	/* TODO(chriskirkland): Add additional validation to SAT issuance:
	* Validate the Session belongs to the User (if provided)
	* Validate the User is not suspended (matches Authentication validation)
	* Validate the session is valid (matches Authentication validation)
	 */

	var tok string
	if req.SessionId != 0 {
		tok, err = sat.GenerateV3SessionToken(int64(req.SessionId), req.Scope, user.TokenSecret.String, req.ExpiresAtTime.AsTime(), attrs)
	} else {
		tok, err = sat.GenerateV3Token(int64(req.UserId), req.Scope, user.TokenSecret.String, req.ExpiresAtTime.AsTime(), attrs)
	}

	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("token issue error")
		resp.Error = err.Error()
		return resp, err
	}

	resp.Token = tok
	resp.ExpiresAtTime = req.ExpiresAtTime
	statter := diagnostics.Statter(ctx)
	statter.Counter("issue_session_sat.count", nil, 1)
	statter.DistributionMs("issue_session_sat.duration", nil, time.Since(startTime))
	return resp, nil
}

func validateAuthTokenRequest(req *pb.IssueSignedAuthTokenRequest) (err error) {
	now := time.Now()
	if req.UserId == 0 {
		err = errors.New("User ID not provided")
	} else if req.Scope == "" {
		err = errors.New("Token scope empty or missing")
	} else if req.ExpiresAtTime.AsTime().Before(now) {
		err = errors.New("Token expiration must be in the future")
	} else if req.ExpiresAtTime.AsTime().After(now.Add(30 * 24 * time.Hour)) {
		// Note that this validation is not present in the monolith, as for
		// historical reasons it has to support tokens with expiration >90 days.
		// As this represents a potential security vulnerability, it pays to
		// diverge from dotcom behavior here.
		err = errors.New("Token expiration must be <30 days from now")
	}
	return err
}

// VerifyCredentials verifies that given credentials are valid, working credentials.
func (c *CredentialManager) VerifyCredentials(ctx context.Context, req *pb.VerifyRequest) (*pb.BatchVerifyResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "verify_credentials")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "CredentialManager.VerifyCredentials")
	defer span.End()

	diagnostics.Logger(ctx).Info("received VerifyCredentials request")
	resp, err := c.verify(ctx, req)
	if err != nil {
		diagnostics.Logger(ctx).Info("VerifyCredentials error",
			kvp.String("credential_count", fmt.Sprint(len(resp.GetResponses()))), kvp.String("message", err.Error()))
	}

	tags := stats.Tags{"credential_count": strconv.Itoa(len(resp.GetResponses()))}
	statter := diagnostics.Statter(ctx)
	statter.Counter("verify_credentials.count", tags, 1)
	statter.Distribution("verify_credentials.size", nil, float64(len(resp.GetResponses())))
	statter.DistributionMs("verify_credentials.duration", tags, time.Since(startTime))
	return resp, err
}

func (c *CredentialManager) verify(ctx context.Context, req *pb.VerifyRequest) (*pb.BatchVerifyResponse, error) {
	statter := diagnostics.Statter(ctx)

	if len(req.Candidates) > MaxVerifyCredentialBatchSize {
		return nil, twirp.NewError(twirp.InvalidArgument, "exceeded candidate limit")
	}

	responses := make([]*pb.VerifyResponse, len(req.Candidates))

	for i, cred := range req.Candidates {
		attributes, err := c.verifyCredential(ctx, cred)

		responses[i] = &pb.VerifyResponse{
			IsVerified: len(attributes) > 0,
			Result:     pb.VerifyResponse_RESULT_SUCCESS,
		}

		var failure *apimodels.AuthenticationFailure
		if errors.As(err, &failure) {
			switch failure.Code {
			case pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED:
				responses[i].Result = pb.VerifyResponse_RESULT_EXPIRED
			case pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED:
				responses[i].Result = pb.VerifyResponse_RESULT_REVOKED
			case pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED:
				responses[i].Result = pb.VerifyResponse_RESULT_FAILED_NOT_SUPPORTED
			case pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND:
				responses[i].Result = pb.VerifyResponse_RESULT_NOT_FOUND
			case pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID:
				responses[i].Result = pb.VerifyResponse_RESULT_FAILED_CREDENTIAL_INVALID
			default:
				responses[i].Result = pb.VerifyResponse_RESULT_FAILED_GENERIC
			}
		}

		if responses[i].IsVerified {
			expiresAt := apimodels.GetAttributeById(attributes, client.CredentialExpiresAtAttribute)
			if expiresAt != nil {
				responses[i].ExpiresAt = expiresAt.GetValue().GetTimeValue()
			}

			accessID := apimodels.GetAttributeById(attributes, client.ProgrammaticAccessIDAttribute)
			if accessID != nil {
				responses[i].AccessId = accessID.Value.GetIntegerValue()
			}

			actorIDAttr := apimodels.GetAttributeById(attributes, client.ActorIDAttribute)
			if actorIDAttr != nil {
				responses[i].ActorId = actorIDAttr.Value.GetIntegerValue()
			}
			credentialIDAttr := apimodels.GetAttributeById(attributes, client.CredentialIDAttribute)
			if actorIDAttr != nil {
				responses[i].CredentialId = credentialIDAttr.Value.GetIntegerValue()
			}
		}

		if err != nil {
			_, ok := err.(twirp.Error)
			if ok {
				responses[i].Message = err.Error()
			}
		}

		tags := stats.Tags{"result": fmt.Sprint(responses[i].IsVerified), "credential_type": pb.CredentialTypeName(cred)}
		statter.Counter("verify_credentials_by_credential.each", tags, 1)
	}

	return &pb.BatchVerifyResponse{
		Responses: responses,
	}, nil
}

func (c *CredentialManager) verifyCredential(ctx context.Context, credential *pb.Credentials) ([]*pb.Attribute, error) {
	switch pb.CredentialTypeName(credential) {
	case "access_token":
		return c.verifyAccessTokenByCredential(ctx, credential)
	default:
		return nil, twirp.NewError(twirp.Unimplemented, "unsupported credential type")
	}
}

func (c *CredentialManager) verifyAccessTokenByCredential(ctx context.Context, credential *pb.Credentials) ([]*pb.Attribute, error) {
	token := credential.GetAccessToken()
	tk := token.GetToken()

	if tk == "" {
		return nil, twirp.RequiredArgumentError("candidates.access_token.token")
	}

	parsed, err := fgpat.ParseToken(tk)
	if err != nil {
		return nil, nil // failure to parse the token won't be meaningful to the caller
	}

	return c.mint.ValidateToken(ctx, parsed)
}

// RevokeCredentials revokes a batch of credentials.
func (c *CredentialManager) RevokeCredentials(ctx context.Context, req *pb.RevokeRequest) (*pb.BatchRevokeResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "revoke_credentials")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "CredentialManager.RevokeCredentials")
	defer span.End()

	diagnostics.Logger(ctx).Info("received RevokeCredentials request", kvp.String("gh.authnd.credentials.request.reason", req.Reason))
	var resp *pb.BatchRevokeResponse
	var err error

	switch req.GetKind().(type) {
	case *pb.RevokeRequest_ByCredential:
		resp = c.revokeCredentialsByCredentials(ctx, req)
	case *pb.RevokeRequest_ById:
		resp = c.revokeCredentialsByIDs(ctx, req)
	default:
		err = twirp.NewError(twirp.Unimplemented, "not implemented")
	}

	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("RevokeCredentials error",
			kvp.String("gh.authnd.credentials.request.credential_count", fmt.Sprint(len(resp.GetResponses()))))
	}

	tags := stats.Tags{"credential_count": fmt.Sprint(len(resp.GetResponses())), "is_exposed": strconv.FormatBool(req.Reason == RevokeReasonCredentialExposed)}
	statter := diagnostics.Statter(ctx)
	statter.Counter("revoke_credentials.count", tags, 1)
	statter.Distribution("revoke_credentials.size", nil, float64(len(resp.GetResponses())))
	statter.DistributionMs("revoke_credentials.duration", tags, time.Since(startTime))
	return resp, err
}

func (c *CredentialManager) revokeCredentialsByCredentials(ctx context.Context, req *pb.RevokeRequest) *pb.BatchRevokeResponse {
	statter := diagnostics.Statter(ctx)

	credentials := req.GetByCredential().Credentials
	responses := make([]*pb.RevokeResponse, len(credentials))

	if len(credentials) > MaxRevokeBatchSize {
		for i := range responses {
			responses[i] = &pb.RevokeResponse{
				Result: pb.RevokeResponse_RESULT_FAILED_MAX_BATCH_SIZE_EXCEEDED,
			}
		}
	} else if req.Reason == "" {
		for i := range responses {
			responses[i] = &pb.RevokeResponse{
				Result: pb.RevokeResponse_RESULT_FAILED_MISSING_REASON,
			}
		}
	} else {
		for i, cred := range credentials {
			revokeResult, err := c.revokeCredentialByCredential(ctx, cred, req.Reason)
			responses[i] = &pb.RevokeResponse{
				Result: apimodels.RevokeResponseResultMap[revokeResult],
			}
			if err != nil {
				responses[i].Message = err.Error()
			}

			tags := stats.Tags{"result": responses[i].Result.String(), "credential_type": pb.CredentialTypeName(cred)}
			statter.Counter("revoke_credentials_by_credential.each", tags, 1)
		}
	}

	return &pb.BatchRevokeResponse{
		Responses: responses,
	}
}

func (c *CredentialManager) revokeCredentialByCredential(ctx context.Context, credential *pb.Credentials, reason string) (apimodels.RevokeResult, error) {
	switch pb.CredentialTypeName(credential) {
	case "login_password":
		return apimodels.RevokeResult_NotSupported, nil
	case "ssh_public_key":
		return apimodels.RevokeResult_NotSupported, nil
	case "access_token":
		return c.revokeAccessTokenByCredential(ctx, credential, reason)
	case "signed_auth_token":
		return apimodels.RevokeResult_NotSupported, nil
	default:
		return apimodels.RevokeResult_Error, errors.Errorf("unknown credential type: %T", credential.GetKind())
	}
}

func (c *CredentialManager) revokeAccessTokenByCredential(ctx context.Context, credential *pb.Credentials, reason string) (apimodels.RevokeResult, error) {
	token := credential.GetAccessToken()
	tk := token.GetToken()

	if tk == "" {
		return apimodels.RevokeResult_Error, twirp.RequiredArgumentError("credentials.access_token.token")
	}

	logger := diagnostics.Logger(ctx)
	parsed, err := fgpat.ParseToken(tk)
	if err != nil {
		logger.WithError(err).Debug("failed to parse token")
		return apimodels.RevokeResult_CredentialInvalid, nil
	}
	logger.Debug("successfully parsed token", kvp.String("gh.authnd.credentials.credential.prefix", string(parsed.Prefix)))

	switch parsed.Prefix {
	case fgpat.UnknownPrefix:
		return apimodels.RevokeResult_NotSupported, nil
	case fgpat.V1Prefix, fgpat.LegacyV1Prefix:
		result, err := c.store.RevokeProgrammaticAccessTokenByHash(ctx, parsed.Hash())
		if result == apimodels.RevokeResult_Success {
			findToken := func(ctx context.Context) (*models.ProgrammaticAccessToken, error) {
				return c.store.FindProgrammaticAccessTokenByHash(ctx, parsed.Hash())
			}
			go c.emitProgrammaticAccessEvent(ctx, schema.ProgrammaticAccessEvent_REVOKED, reason, findToken)
		}
		return result, err
	default:
		return apimodels.RevokeResult_Error, errors.Errorf("unexpected token prefix: %s", parsed.Prefix)
	}
}

func (c *CredentialManager) revokeCredentialsByIDs(ctx context.Context, req *pb.RevokeRequest) *pb.BatchRevokeResponse {
	statter := diagnostics.Statter(ctx)

	typ := req.GetById().CredentialType
	ids := req.GetById().CredentialIds
	responses := make([]*pb.RevokeResponse, len(ids))

	if len(ids) > MaxRevokeBatchSize {
		for i := range responses {
			responses[i] = &pb.RevokeResponse{
				Result: pb.RevokeResponse_RESULT_FAILED_MAX_BATCH_SIZE_EXCEEDED,
			}
		}
	} else if req.Reason == "" {
		for i := range responses {
			responses[i] = &pb.RevokeResponse{
				Result: pb.RevokeResponse_RESULT_FAILED_MISSING_REASON,
			}
		}
	} else {
		for i, id := range ids {
			revokeResult, err := c.revokeCredentialByID(ctx, typ, id, req.Reason)
			responses[i] = &pb.RevokeResponse{
				Result: apimodels.RevokeResponseResultMap[revokeResult],
			}
			if err != nil {
				responses[i].Message = err.Error()
			}

			tags := stats.Tags{"result": responses[i].Result.String(), "credential_type": typ}
			statter.Counter("revoke_credentials_by_id.each", tags, 1)
		}
	}

	return &pb.BatchRevokeResponse{
		Responses: responses,
	}
}

func (c *CredentialManager) revokeCredentialByID(ctx context.Context, credentialType string, id int64, reason string) (apimodels.RevokeResult, error) {
	switch credentialType {
	case pb.ProgrammaticAccessTokenType:
		result, err := c.store.RevokeProgrammaticAccessTokenByID(ctx, uint64(id))
		if result == apimodels.RevokeResult_Success {
			findToken := func(ctx context.Context) (*models.ProgrammaticAccessToken, error) {
				return c.store.FindProgrammaticAccessTokenByID(ctx, uint64(id))
			}
			go c.emitProgrammaticAccessEvent(ctx, schema.ProgrammaticAccessEvent_REVOKED, reason, findToken)
		}
		return result, err
	default:
		return apimodels.RevokeResult_Error, errors.Errorf("unknown credential type: %s", credentialType)
	}
}

func (c *CredentialManager) emitProgrammaticAccessEvent(ctx context.Context, event schema.ProgrammaticAccessEventEventType, reason string, findToken func(ctx context.Context) (*models.ProgrammaticAccessToken, error)) {
	startTime := time.Now()
	// We _don't_ want cancellation of the parent context to cancel the message publishing
	ctx, cancel := context.WithTimeout(ctxutil.DetachedCancel(ctx), 3*time.Second)
	defer cancel()

	requestId := requestid.GetGitHubRequestID(ctx)

	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.hydro.event.type", event.String()), kvp.String("gh.authnd.hydro.event.reason", reason))
	ctx = diagnostics.WithStatterTags(ctx, stats.Tags{"event_type": event.String()})
	statter := diagnostics.Statter(ctx)

	token, err := findToken(ctx)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("Unable to lookup token from emitProgrammaticAccessEvent")
		statter.Counter("programmatic_access.event.error", nil, 1)
		return
	}

	ctx = diagnostics.WithLoggerFields(ctx, kvp.Uint64("gh.actor_id", token.MintTokenCommon.ActorID))
	logger := diagnostics.Logger(ctx)

	service := middleware.GetCatalogService(ctx)
	shouldNotify := (reason != RevokeReasonCredentialExposed) && service != "authnd_tester"

	message := schema.ProgrammaticAccessEvent{
		ActorId:               int64(token.MintTokenCommon.ActorID),
		CredentialId:          int64(token.ID),
		AccessId:              int64(token.AccessID),
		CredentialSuffix:      string(token.TokenSuffix),
		CredentialIssuedAtUtc: timestamppb.New(token.MintTokenCommon.IssuedAt),
		EventType:             event,
		EventReason:           reason,
		RequestId:             requestId,
		CatalogService:        service,
		SendNotification:      shouldNotify,
	}
	if token.MintTokenCommon.ExpiresAt.Valid {
		message.CredentialExpiresAtUtc = timestamppb.New(token.MintTokenCommon.ExpiresAt.Time)
	}

	if tenant := tenancy.GetTenantContext(ctx); tenant != nil {
		message.TenantId = int64(tenant.ID)
	}

	err = c.publisher.PublishEvent(ctx, message)
	if err != nil {
		logger.WithError(err).Info("Unable to publish event from emitProgrammaticAccessEvent", kvp.Uint64("gh.authnd.credentials.credential.id", token.ID))
		statter.Counter("programmatic_access.event.error", nil, 1)
	} else {
		// publish and set last_event_at_utc on the token
		err = c.store.MarkEventForProgrammaticAccessTokens(ctx, []uint64{token.ID})
		if err != nil {
			logger.WithError(err).Info("Unable to mark tokens as notified from emitProgrammaticAccessEvent", kvp.Uint64("gh.authnd.credentials.credential.id", token.ID))
			statter.Counter("programmatic_access.event.mark.error", nil, 1)
		}
	}

	statter.DistributionMs("programmatic_access.event.duration", nil, time.Since(startTime))
}

func parseBaseAttributes(attrs []*pb.Attribute) (*basePromotedAttributes, error) {
	result := &basePromotedAttributes{}
	dupeCheck := make(map[string]bool)

	for _, attr := range attrs {
		if dupeCheck[attr.Id] {
			return result, newDuplicateAttributeError(attr.Id)
		}
		dupeCheck[attr.Id] = true

		switch attr.Id {
		case client.ActorIDAttribute:
			if v, ok := attr.Value.Kind.(*pb.Value_IntegerValue); ok {
				result.ActorID = uint64(v.IntegerValue)
			} else {
				return result, newTypeMismatchError(attr.Id, pb.IntegerKind, attr.Value)
			}
		case client.ActorTypeAttribute:
			if v, ok := attr.Value.Kind.(*pb.Value_StringValue); ok {
				result.ActorType = v.StringValue
			} else {
				return result, newTypeMismatchError(attr.Id, pb.StringKind, attr.Value)
			}
		case client.CredentialIDAttribute, client.CredentialTypeAttribute:
			return result, newInvalidAttributeError(attr.Id)
		}
	}

	if result.ActorID == 0 {
		return result, newMissingRequiredAttributeError(client.ActorIDAttribute)
	}
	if result.ActorType == "" {
		return result, newMissingRequiredAttributeError(client.ActorTypeAttribute)
	}

	return result, nil
}

func (c *CredentialManager) FindCredentials(ctx context.Context, req *pb.FindCredentialsRequest) (*pb.FindCredentialsResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "find_credentials")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "CredentialManager.FindCredentials")
	defer span.End()

	diagnostics.Logger(ctx).Info("received FindCredentials request")

	if req.Type != pb.ProgrammaticAccessTokenType {
		return &pb.FindCredentialsResponse{
			Result: pb.FindCredentialsResponse_RESULT_FAILED_NOT_SUPPORTED,
			Error:  fmt.Sprintf("specified credential type '%s' is not supported", req.Type),
		}, nil
	}

	attrs, err := parsePrATAttributes(req.Attributes)
	if err != nil {
		return &pb.FindCredentialsResponse{
			Result: pb.FindCredentialsResponse_RESULT_FAILED_INVALID_ATTRIBUTES,
			Error:  err.Error(),
		}, nil
	}

	for _, attr := range req.Attributes {
		if attr.Id != client.ActorIDAttribute && attr.Id != client.ActorTypeAttribute && attr.Id != client.ProgrammaticAccessIDAttribute {
			return &pb.FindCredentialsResponse{
				Result: pb.FindCredentialsResponse_RESULT_FAILED_INVALID_ATTRIBUTES,
				Error:  newInvalidQueryAttributeError(attr.Id).Error(),
			}, nil
		}
	}

	// if we are in a proxima environment, kickoff user validation in the background to
	// ensure they exist and that they are valid
	var awaitUser utils.AwaitUserValidationFunc
	var cancelUserLookup context.CancelFunc
	if tenancy.GetTenantContext(ctx) != nil {
		awaitUser, cancelUserLookup = utils.ValidateUserInBackground(ctx, func(innerContext context.Context) (*models.User, error) {
			return c.store.FindUserByID(innerContext, int64(attrs.ActorID))
		}, utils.AllowSuspendedUsers())
	}

	tokens, err := c.store.FindProgrammaticAccessTokens(ctx, int64(attrs.ActorID), attrs.ActorType, int64(attrs.AccessID))
	if err != nil {
		if cancelUserLookup != nil {
			cancelUserLookup()
		}
		return nil, errors.WithStack(err)
	}

	entries := make([]*pb.AttributeList, 0, len(tokens))
	for _, token := range tokens {
		ats := []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(token.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(token.TokenSuffix)),
		}
		if token.ExpiresAt.Valid {
			ats = append(ats, pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, token.ExpiresAt.Time))
		}

		entries = append(entries, &pb.AttributeList{
			Attributes: ats,
		})
	}

	// if we kicked off the user validation above, await it here
	// awaiting it here allows the FindProgrammaticAccessTokens call to run in parallel
	if awaitUser != nil {
		user, err := awaitUser()
		if err != nil {
			return &pb.FindCredentialsResponse{
				Result: pb.FindCredentialsResponse_RESULT_FAILED_GENERIC,
				Error:  err.Error(),
			}, nil
		}
		if user == nil {
			return &pb.FindCredentialsResponse{
				Result: pb.FindCredentialsResponse_RESULT_FAILED_USER_UNKNOWN,
			}, nil
		}
	}

	// Return the response
	resp := &pb.FindCredentialsResponse{
		Result:      pb.FindCredentialsResponse_RESULT_SUCCESS,
		Credentials: entries,
	}

	tags := stats.Tags{"credential_count": fmt.Sprint(len(entries)), "credential_type": req.Type}
	statter := diagnostics.Statter(ctx)
	statter.Counter("find_credentials.count", tags, 1)
	statter.Distribution("find_credentials.results", tags, float64(len(entries)))
	statter.DistributionMs("find_credentials.duration", tags, time.Since(startTime))

	return resp, nil
}

func parsePrATAttributes(attrs []*pb.Attribute) (*PrATPromotedAttributes, error) {
	baseAttrs, err := parseBaseAttributes(attrs)
	if err != nil {
		return nil, err
	}
	result := &PrATPromotedAttributes{
		basePromotedAttributes: *baseAttrs,
	}

	for _, attr := range attrs {
		if attr.Id == client.ProgrammaticAccessIDAttribute {
			if v, ok := attr.Value.Kind.(*pb.Value_IntegerValue); ok {
				result.AccessID = uint64(v.IntegerValue)
			} else {
				return result, newTypeMismatchError(attr.Id, pb.IntegerKind, attr.Value)
			}
		}
	}

	return result, nil
}

func newTypeMismatchError(attr string, expectedType string, value *pb.Value) error {
	return errors.New(fmt.Sprintf("attribute '%s' type mismatch, expected '%s' but got '%s'", attr, expectedType, value.GetKindName()))
}

func newMissingRequiredAttributeError(attr string) error {
	return errors.New(fmt.Sprintf("attribute '%s' is required", attr))
}

func newInvalidAttributeError(attr string) error {
	return errors.New(fmt.Sprintf("attribute id '%s' is an invalid or reserved id", attr))
}

func newDuplicateAttributeError(attr string) error {
	return errors.New(fmt.Sprintf("duplicate attribute id '%s'", attr))
}

func newInvalidQueryAttributeError(attr string) error {
	return errors.New(fmt.Sprintf("attribute id '%s' cannot be used in a FindCredentials query", attr))
}
