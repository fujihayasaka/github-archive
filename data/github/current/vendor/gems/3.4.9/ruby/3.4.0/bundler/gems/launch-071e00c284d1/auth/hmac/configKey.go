package hmac

import (
	"context"
	"encoding/base64"

	"github.com/pkg/errors"

	"github.com/github/launch/auth"
)

type ConfigKeyFetcher struct {
	Primary   auth.Key
	Secondary auth.Key
}

func NewConfigKeyFetcher(primaryHmacKey, secondaryHmacKey string) (*ConfigKeyFetcher, error) {
	primary, err := decodeHMACKeyValue(primaryHmacKey)
	if err != nil {
		return nil, errors.Wrap(err, "decoding primary HMAC key")
	}
	secondary, err := decodeHMACKeyValue(secondaryHmacKey)
	if err != nil {
		return nil, errors.Wrap(err, "decoding secondary HMAC key")
	}
	return &ConfigKeyFetcher{Primary: primary, Secondary: secondary}, nil
}

func (c *ConfigKeyFetcher) GetHMACKeys(_ context.Context) ([2]auth.Key, error) {
	hmacKeys := [2]auth.Key{c.Primary, c.Secondary}
	return hmacKeys, nil
}

func decodeHMACKeyValue(hmacKey string) (auth.Key, error) {
	if hmacKey == "" {
		return nil, errors.Errorf("HmacKey is not set in the configuration")
	}

	pKey, err := base64.StdEncoding.DecodeString(hmacKey)
	if err != nil {
		return nil, errors.Wrapf(err, "decoding failed for the hmac key")
	}
	return pKey, nil
}
