package earthsmoke

import (
	"context"
	"encoding/base64"
	"strings"

	diet_earthsmoke "github.com/github/diet_earthsmoke/go"
	"github.com/github/go-kvp"
	gokvp "github.com/github/go-kvp"
	"github.com/hashicorp/go-multierror"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/workflowbuild"
)

// Decryptor decrypts a secret.
type Decryptor interface {
	DecryptSecretValue(ctx context.Context, secretValue, scope string, source workflowbuild.SecretSource) (string, bool, error)
}

// decryptor is an object that knows how to decrypt a secret with earthsmoke.
type decryptor struct {
	log           logger.Logger
	statter       statter.Statter
	secretKeysMap map[workflowbuild.SecretSource]*diet_earthsmoke.HighLevelKey
}

// NewDecryptor returns a new Earthsmoke decryptor
func NewDecryptor(log logger.Logger, statter statter.Statter, secretKeysMap map[workflowbuild.SecretSource]*diet_earthsmoke.HighLevelKey) Decryptor {
	return &decryptor{
		log:           log,
		statter:       statter,
		secretKeysMap: secretKeysMap,
	}
}

// DecryptSecretValue base64 decodes the given secret value, decrypts it
// using Earthsmoke, and returns the result.  Returns the given secret
// value when Earthsmoke is not configured.
func (d *decryptor) DecryptSecretValue(ctx context.Context, secretValue, scope string, source workflowbuild.SecretSource) (string, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	decodedSecretValue, err := base64.StdEncoding.DecodeString(secretValue)
	if err != nil {
		return "", false, tracing.RecordError(span, errors.Wrap(err, "failed to base64 decode secret value"))
	}

	logFields := []kvp.Field{}
	logFields = append(logFields,
		gokvp.String("source", string(source)),
		gokvp.String("scope", scope),
	)

	if string(decodedSecretValue) == "" {
		// Empty secrets are expected as there are around 14k incorrectly encrypted secrets added by users before we started validating secrets created by users through the API
		// Incorrectly encrypted secrets cannot be decrypted fully so an empty string is returned. See https://github.com/github/kredz/blob/main/docs/adr/0006-kredz-allow-list.md
		// The long term plan to is clean up all known incorrectly encrypted secrets https://github.com/github/kredz/issues/857
		// Once known incorrectly encrypted secrets are fixed, we should report to sentry again, for now just logging to splunk as sentry reporting is just noise
		d.log.Debug(ctx, "empty decoded value for secret", logFields...)
		return "", false, nil
	}

	localDecrypted, err := localDecrypt(ctx, decodedSecretValue, scope, source, d.log, d.secretKeysMap)
	if err != nil {
		d.statter.Counter(ctx, "diet_earthsmoke.decrypt", statter.Tags{"status": "failure", "error": "decrypt_error"}, 1)
		return "", false, tracing.RecordError(span, kvperrors.WrapWith(err, logFields...))
	}

	d.statter.Counter(ctx, "diet_earthsmoke.decrypt", statter.Tags{"status": "success"}, 1)
	return localDecrypted, true, nil
}

func localDecrypt(ctx context.Context, decodedSecretValue []byte, scope string, source workflowbuild.SecretSource, log logger.Logger, secretKeysMap map[workflowbuild.SecretSource]*diet_earthsmoke.HighLevelKey) (string, error) {
	dietEarthsmokeHLK, err := source.GetSourceHighLevelKey(secretKeysMap)
	if err != nil {
		return "", err
	}

	// Currently all secrets are encrypted with a key scoped to the entity
	// it belongs to (user, repo, organization, environment).
	// In an earlier iteration of Actions/credz, we used the global `custom-tasks`
	// key to encrypt all Actions repository secrets, see github/github#97335
	// With github/github#100806 and github/launch#886,
	// we moved to per-entity scoped keys.
	// Decrypting unscoped secrets with the scoped-key will fail.
	decryptedSecret, scopedErr := dietEarthsmokeHLK.OpenHighLevel(decodedSecretValue, &scope)
	if scopedErr != nil {

		// We fall back to the unscoped keys here
		// As of November 2021, only a few accounts still have unscoped secrets.
		// For most secrets, this should fail as they likely hit some other error
		// during scoped decryption. Until those are all gone, we can't remove this fallback.
		// See github/c2c-actions-experience#5483 for more details.
		var unscopedErr error
		decryptedSecret, unscopedErr = dietEarthsmokeHLK.OpenHighLevel(decodedSecretValue, nil)

		if unscopedErr != nil {
			if isCipherTextTooShortError(unscopedErr) {
				log.Debug(ctx, "Ciphertext too short, returning empty string value")
				return "", nil
			}

			return "", errors.Wrap(multierror.Append(scopedErr, unscopedErr), "failed to locally decrypt secret value with scoped and unscoped key")
		}
	}

	return string(decryptedSecret), nil
}

// We used to allow users to persist an empty value for the
// secret value, we no longer do allow this but means decrpyting
// the value fails with this error
//
// @ref https://github.com/github/c2c-actions-experience/issues/3046
func isCipherTextTooShortError(err error) bool {
	return err != nil && strings.Contains(err.Error(), "Ciphertext too short")
}
