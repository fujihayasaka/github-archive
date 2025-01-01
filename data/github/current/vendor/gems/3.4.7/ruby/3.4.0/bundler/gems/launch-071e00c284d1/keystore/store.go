package keystore

import (
	"context"
	"crypto/rsa"

	diet_earthsmoke "github.com/github/diet_earthsmoke/go"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"

	"github.com/github/go-kvp"
)

// KeyStore provide a way to encrypt and decrypt a rsa.PrivateKey
// specific to a given organisation
type Store interface {
	EncryptPrivateKeyForOrganization(ctx context.Context, kss *scope, key *rsa.PrivateKey) ([]byte, error)
	DecryptPrivateKeyForOrganization(ctx context.Context, kss *scope, data []byte) (*rsa.PrivateKey, error)
}

type DietEarthsmokeKeyUnmarshaller func(context.Context, string) (DietEarthsmokeKey, error)

type DietEarthsmokeKey interface {
	DecryptHighLevel(cipherText []byte, scope *string) ([]byte, error)
	EncryptHighLevel(cipherText []byte, scope *string) ([]byte, error)
}

func NewStore(keystoreAZPKey string, log logger.Logger, stats statter.Statter) Store {
	return &store{
		ke:                NewEncoder(),
		dietEarthsmokeKey: keystoreAZPKey,
		dietEarthsmokeKeyUnmarshaller: func(ctx context.Context, key string) (DietEarthsmokeKey, error) {
			dietEarthsmokeHLK, err := diet_earthsmoke.UnmarshalHighLevelKey(key)
			if err != nil {
				return nil, errors.Wrap(err, "unable to generate diet earthsmoke high level key")
			}

			return dietEarthsmokeHLK, nil
		},
		log:   log,
		stats: stats,
	}
}

type store struct {
	ke                            Encoder
	dietEarthsmokeKey             string
	dietEarthsmokeKeyUnmarshaller DietEarthsmokeKeyUnmarshaller
	log                           logger.Logger
	stats                         statter.Statter
}

// EncryptPrivateKeyForRepo takes the decrypted private key and returns
// the encrypted private key
func (rks *store) EncryptPrivateKeyForOrganization(ctx context.Context, kss *scope, key *rsa.PrivateKey) ([]byte, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	pem, err := rks.ke.Encode(key)
	if err != nil {
		return nil, err
	}

	logFields := []kvp.Field{}
	logFields = append(logFields,
		kvp.String("scope", kss.Organization),
	)

	dietEarthsmokeHLK, err := rks.dietEarthsmokeKeyUnmarshaller(ctx, rks.dietEarthsmokeKey)
	if err != nil {
		err = errors.Wrap(err, "failed to unmarshal high level key for key store")
		rks.log.Report(ctx, err,
			logFields...,
		)
		rks.stats.Counter(ctx, "keystore.diet_earthsmoke.local_encrypt", statter.Tags{"status": "failure", "error": "key_error"}, 1)
		return nil, err
	}

	encryptedPEM, err := dietEarthsmokeHLK.EncryptHighLevel(pem, &kss.Organization)
	if err != nil {
		err = errors.Wrap(err, "failed to encrypt secret using diet earthsmoke")
		rks.log.Report(ctx, err,
			logFields...,
		)
		rks.stats.Counter(ctx, "keystore.diet_earthsmoke.local_encrypt", statter.Tags{"status": "failure", "error": "local_encrypt_error"}, 1)
		return nil, err
	}

	rks.stats.Counter(ctx, "keystore.diet_earthsmoke.local_encrypt", statter.Tags{"status": "success"}, 1)
	return encryptedPEM, nil
}

// DecryptPrivateKeyForRepo takes the encrypted private key and returns
// the decrypted *rsa.PrivateKey
func (rks *store) DecryptPrivateKeyForOrganization(ctx context.Context, kss *scope, data []byte) (*rsa.PrivateKey, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	logFields := []kvp.Field{}
	logFields = append(logFields,
		kvp.String("scope", kss.Organization),
	)

	dietEarthsmokeHLK, err := rks.dietEarthsmokeKeyUnmarshaller(ctx, rks.dietEarthsmokeKey)
	if err != nil {
		err = errors.Wrap(err, "failed to unmarshal high level key for key store")
		rks.log.Report(ctx, err,
			logFields...)
		rks.stats.Counter(ctx, "keystore.diet_earthsmoke.local_decrypt", statter.Tags{"status": "failure", "error": "key_error"}, 1)
		return nil, err
	}

	pem, err := dietEarthsmokeHLK.DecryptHighLevel(data, &kss.Organization)
	if err != nil {
		err = errors.Wrap(err, "failed to decrypt secret using diet earthsmoke")
		rks.log.Report(ctx, err,
			logFields...)
		rks.stats.Counter(ctx, "keystore.diet_earthsmoke.local_decrypt", statter.Tags{"status": "failure", "error": "local_decrypt_error"}, 1)
		return nil, err
	}

	rks.stats.Counter(ctx, "keystore.diet_earthsmoke.local_decrypt", statter.Tags{"status": "success"}, 1)
	return rks.ke.Decode(pem)
}
