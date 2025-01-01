package validators

import (
	"context"
	"database/sql"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/ssh"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
)

type SSHPublicKeyValidatorInterface interface {
	ValidatePublicKey(ctx context.Context, key string) ([]*pb.Attribute, error)
}

// SSHPublicKeyValidator owns the stores and logic nessesary to validate SSH public keys
type SSHPublicKeyValidator struct {
	Store store.PublicKeysStore
}

// ValidatePublicKey validates an OpenSSH formatted public key.
func (v *SSHPublicKeyValidator) ValidatePublicKey(ctx context.Context, key string) ([]*pb.Attribute, error) {
	ctx, span := tracing.ChildSpan(ctx, "SSHPublicKeyValidator.ValidatePublicKey")
	defer span.End()

	fingerprint, err := ssh.GenerateSHA256(key)
	if err != nil {
		return nil, err
	}
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.authenticator.credential.fingerprint", fingerprint))
	diagnostics.Logger(ctx).Info("validating ssh public key")

	publicKey, err := v.Store.FindPublicKeyBySHA256Fingerprint(ctx, fingerprint)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Error("failed to find public key")

		if errors.Is(err, sql.ErrNoRows) {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_NOT_FOUND}
		} else if errors.Is(err, common.StoreErrUnsupported) {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
		} else if errors.Is(err, common.StoreErrUnexpectedMultipleResults) {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_MISMATCH}
		}
		return nil, err
	}

	encodedKey, err := ssh.RemoveOptionalComment(key)
	if err != nil {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_MALFORMED}
	} else if publicKey.Key != encodedKey {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_MISMATCH}
	}

	// check if user ssh key
	if publicKey.UserID.Valid {
		attributes := []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, publicKey.UserID.Int64),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.CredentialIDAttribute, publicKey.ID),
			pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
		}

		if !publicKey.IsVerified() {
			attributes = append(attributes, pb.NewBoolAttribute(client.PublicKeyNotVerifiedAttribute, true))
		}

		return attributes, nil
	}

	// check if a deploy key
	if publicKey.RepositoryID.Valid {
		return []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, publicKey.RepositoryID.Int64),
			pb.NewStringAttribute(client.ActorTypeAttribute, "Repository"),
			pb.NewInt64Attribute(client.CredentialIDAttribute, publicKey.ID),
			pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
		}, nil
	}

	return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN}
}
