package exchanger

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"sync"
	"time"

	"github.com/pkg/errors"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/authenticator"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/go-stats"
	jwt "github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/twitchtv/twirp"
)

const maxExpirationSeconds = 60

// NewTokenExchangerServer returns a new TokenExchanger v0 TwirpServer for the given AuthStore.
func NewTokenExchangerServer(
	store store.Store,
	hooks *twirp.ServerHooks,
	signingKey *ecdsa.PrivateKey,
	isEnterpriseServer bool,
) (pb.TwirpServer, error) {
	exchanger := &TokenExchanger{
		authnr:     authenticator.NewAuthenticator(store, isEnterpriseServer),
		signingKey: signingKey,
	}
	// ensure we can calculate the KID before we start serving requests
	if _, err := exchanger.getKID(); err != nil {
		return nil, errors.WithStack(err)
	}

	return pb.NewTokenExchangerServer(exchanger, hooks), nil
}

type TokenExchanger struct {
	authnr     pb.Authenticator
	signingKey *ecdsa.PrivateKey
}

func (t *TokenExchanger) ExchangeToken(
	ctx context.Context,
	req *pb.ExchangeTokenRequest,
) (*pb.ExchangeTokenResponse, error) {
	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "TokenExchanger.ExchangeToken")
	defer span.End()

	tags := stats.Tags{
		"result":          "failed",
		"token_exchanger": "true",
	}
	defer func() {
		statter := diagnostics.Statter(ctx)
		statter.Counter("token_exchange.count", tags, 1)
		statter.DistributionMs("token_exchange.duration", tags, time.Since(startTime))
	}()

	diagnostics.WithLoggerFields(ctx, kvp.Bool("token_exchanger", true))
	diagnostics.Logger(ctx).Info("received token exchange request")

	var accessToken string
	creds := req.GetCredentials()
	switch creds.GetKind().(type) {
	case *pb.Credentials_AccessToken:
		accessToken = creds.GetAccessToken().GetToken()
	default:
		return nil, twirp.NewErrorf(twirp.InvalidArgument, "unsupported credential kind %s", pb.CredentialTypeName(creds))
	}

	resp, err := t.authnr.Authenticate(ctx, &pb.AuthenticateRequest{
		Credentials: pb.NewAccessTokenCredential(accessToken),
	})
	if err != nil {
		return nil, err
	}
	diagnostics.Logger(ctx).Info("authenticated token", kvp.String("result", resp.Result.String()))

	if resp.Result != pb.AuthenticateResponse_RESULT_SUCCESS {
		tags["result"] = resp.Result.String()
		return &pb.ExchangeTokenResponse{Result: resp.Result}, nil
	}

	_, jspan := tracing.ChildSpan(ctx, "TokenExchanger.GenerateJWT")
	defer jspan.End()

	claims, err := claimsFromAttributes(resp.Attributes)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Error("failed to translate attributes to claims")
		return &pb.ExchangeTokenResponse{Result: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}, nil
	}

	token := jwt.NewWithClaims(jwt.SigningMethodES256, claims)
	kid, err := t.getKID()
	if err != nil {
		// this should not be possible because the KID is calculated and memoized at startup
		diagnostics.Logger(ctx).WithError(err).Error("failed to get KID")
		return &pb.ExchangeTokenResponse{Result: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}, nil
	}
	token.Header["kid"] = kid

	signed, err := token.SignedString(t.signingKey)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Error("failed to sign token")
		return &pb.ExchangeTokenResponse{Result: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}, nil
	}

	return &pb.ExchangeTokenResponse{
		Result:    pb.AuthenticateResponse_RESULT_SUCCESS,
		Token:     signed,
		ExpiresAt: timestamppb.New(claims.ExpiresAt.Time),
	}, nil
}

var (
	signingKeyOnce sync.Once
	signingKeyID   string
)

func (t *TokenExchanger) getKID() (string, error) {
	var err error
	signingKeyOnce.Do(func() {
		var publicKey string
		publicKey, err = crypto.GetBase64EncodedPublicKey(t.signingKey)
		if err != nil {
			err = errors.Wrap(err, "failed to encode public key")
			return
		}

		signingKeyID, err = crypto.GenerateECDSAFingerprint(publicKey)
		if err != nil {
			err = errors.Wrap(err, "failed to generate kid")
			return
		}
	})
	return signingKeyID, err

}

func claimsFromAttributes(attrs []*pb.Attribute) (*client.ExchangeTokenClaims, error) {
	claims := &client.ExchangeTokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			//TODO(chriskirkland): decide whether we should use the default `sub` claim which must
			// unique define the Identity represented in the JWT.
			ID:        uuid.New().String(),
			Issuer:    "github/authnd",
			NotBefore: jwt.NewNumericDate(time.Now().UTC().Add(-5 * time.Second)),
			ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(maxExpirationSeconds * time.Second)),
		},
	}
	for _, attr := range attrs {
		switch attr.Id {
		// standard JWT claims
		case client.CredentialExpiresAtAttribute:
			// NOTE(chriskirkland): settings credential.expires_at_utc attribute to the JWT expiration may cause
			// some wonkiness, but there's security risk to leaving it as the expiration of the upstream access
			// token.
			accessTokenExpiration := timeFromAttribute(attr)
			if claims.ExpiresAt.Time.After(accessTokenExpiration) {
				claims.RegisteredClaims.ExpiresAt = jwt.NewNumericDate(accessTokenExpiration)
			}
		case client.CredentialIssuedAtAttribute:
			claims.RegisteredClaims.IssuedAt = jwt.NewNumericDate(timeFromAttribute(attr))

		// custom claims
		case client.ActorIDAttribute:
			claims.ActorID = uintFromAttribute(attr)
		case client.ActorTypeAttribute:
			claims.ActorType = stringFromAttribute(attr)
		case client.UserLoginAttribute:
			claims.UserLogin = stringFromAttribute(attr)
		case client.CredentialIDAttribute:
			claims.CredentialID = uintFromAttribute(attr)
		case client.CredentialTypeAttribute:
			claims.CredentialType = stringFromAttribute(attr)
		case client.CredentialScopesAttribute:
			claims.CredentialScopes = stringListFromAttribute(attr)
		case client.CredentialCreatedAtAttribute:
			claims.CredentialCreatedAtAttribute = jwt.NewNumericDate(timeFromAttribute(attr))
		case client.TokenSuffixAttribute:
			claims.TokenSuffix = stringFromAttribute(attr)
		case client.ProgrammaticAccessIDAttribute:
			claims.AccessID = uintFromAttribute(attr)
		case client.OrganizationSSOAuthorizedIdsAttribute:
			claims.OrganizationSSOAuthorizedIDs = uintListFromAttribute(attr)
		case client.ApplicationIDAttribute:
			claims.ApplicationID = uintFromAttribute(attr)
		case client.ApplicationTypeAttribute:
			claims.ApplicationType = stringFromAttribute(attr)
		case client.ApplicationClientIDAttribute:
			claims.ApplicationClientID = stringFromAttribute(attr)
		case client.ApplicationOwnerIDAttribute:
			claims.ApplicationOwnerID = uintFromAttribute(attr)
		case client.ApplicationOwnerTypeAttribute:
			claims.ApplicationOwnerType = stringFromAttribute(attr)
		case client.InstallationIDAttribute:
			claims.InstallationID = uintFromAttribute(attr)
		case client.InstallationTargetIDAttribute:
			claims.InstallationTargetID = uintFromAttribute(attr)
		case client.InstallationTargetTypeAttribute:
			claims.InstallationTargetType = stringFromAttribute(attr)
		case client.ScopedInstallationIDAttribute:
			claims.ScopedInstallationID = uintFromAttribute(attr)
		case client.ScopedInstallationTypeAttribute:
			claims.ScopedInstallationType = stringFromAttribute(attr)
		default:
			if claims.ExchangeTokenDynamicClaims == nil {
				claims.ExchangeTokenDynamicClaims = make(map[string]interface{})
			}
			if attr.Value == nil {
				return nil, fmt.Errorf("dynamic attribute %s value is nil", attr.Id)
			}
			switch attr.GetValue().GetKindName() {
			case pb.BoolKind:
				claims.ExchangeTokenDynamicClaims[attr.Id] = attr.GetValue().GetBoolValue()
			case pb.IntegerKind:
				claims.ExchangeTokenDynamicClaims[attr.Id] = attr.GetValue().GetIntegerValue()
			case pb.DoubleKind:
				claims.ExchangeTokenDynamicClaims[attr.Id] = attr.GetValue().GetDoubleValue()
			case pb.StringKind:
				claims.ExchangeTokenDynamicClaims[attr.Id] = attr.GetValue().GetDoubleValue()
			case pb.StringListKind:
				claims.ExchangeTokenDynamicClaims[attr.Id] = attr.GetValue().GetStringListValue()
			case pb.IntegerListKind:
				claims.ExchangeTokenDynamicClaims[attr.Id] = attr.GetValue().GetIntegerListValue()
			default:
				return nil, fmt.Errorf("dynamic attribute %s has unknown kind %s", attr.Id, attr.GetValue().GetKindName())
			}
		}
	}
	return claims, nil
}

func uintFromAttribute(attr *pb.Attribute) *uint64 {
	if attr == nil {
		return nil
	}
	value := attr.GetValue()
	if value == nil {
		return nil
	}
	val := uint64(value.GetIntegerValue())
	return &val
}

func stringFromAttribute(attr *pb.Attribute) *string {
	if attr == nil {
		return nil
	}
	value := attr.GetValue()
	if value == nil {
		return nil
	}
	val := value.GetStringValue()
	return &val
}

func timeFromAttribute(attr *pb.Attribute) time.Time {
	var t time.Time
	if attr == nil {
		return t
	}
	value := attr.GetValue()
	if value == nil {
		return t
	}
	if val := value.GetTimeValue(); val.IsValid() {
		return val.AsTime()
	}
	return t
}

func stringListFromAttribute(attr *pb.Attribute) []string {
	if attr == nil {
		return nil
	}
	value := attr.GetValue()
	if value == nil {
		return nil
	}
	if vals := value.GetStringListValue(); vals != nil {
		return vals.Values
	}
	return nil
}

func uintListFromAttribute(attr *pb.Attribute) []uint64 {
	if attr == nil {
		return nil
	}
	value := attr.GetValue()
	if value == nil {
		return nil
	}
	if vals := value.GetIntegerListValue(); vals != nil {
		uvals := make([]uint64, len(vals.Values))
		for ix, val := range vals.Values {
			uvals[ix] = uint64(val)
		}
		return uvals
	}
	return nil
}
