package hmac

import (
	"context"
	"encoding/json"

	"github.com/pkg/errors"

	"github.com/github/launch/auth"
	"github.com/github/launch/pkg/azp"
)

type VaultKeyFetcher struct {
	PrimaryHmacKeyName   string
	SecondaryHmacKeyName string
	KeyVaultName         string
	KeyVaultClient       azp.KeyVaultClient
}

func NewVaultKeyFetcher(PrimaryHmacKeyName string, SecondaryHmacKeyName string, KeyVaultName string, KeyVaultClient azp.KeyVaultClient) *VaultKeyFetcher {
	return &VaultKeyFetcher{
		PrimaryHmacKeyName:   PrimaryHmacKeyName,
		SecondaryHmacKeyName: SecondaryHmacKeyName,
		KeyVaultName:         KeyVaultName,
		KeyVaultClient:       KeyVaultClient,
	}
}

func (v *VaultKeyFetcher) GetHMACKeys(ctx context.Context) ([2]auth.Key, error) {
	var hmacKeys [2]auth.Key
	key, err := v.getHmacKeyFromVault(ctx, v.PrimaryHmacKeyName)
	if err != nil {
		err = errors.Wrapf(err, "fetching %s", v.PrimaryHmacKeyName)
		return hmacKeys, err
	}
	hmacKeys[0] = key
	key, err = v.getHmacKeyFromVault(ctx, v.SecondaryHmacKeyName)
	if err != nil {
		err = errors.Wrapf(err, "fetching %s", v.SecondaryHmacKeyName)
		return hmacKeys, err
	}
	hmacKeys[1] = key
	return hmacKeys, nil
}

func (v *VaultKeyFetcher) getHmacKeyFromVault(ctx context.Context, vaultKeyName string) (auth.Key, error) {
	secret, err := v.KeyVaultClient.GetSecret(ctx, v.KeyVaultName, vaultKeyName)
	if err != nil {
		return nil, err
	}

	var hmacKeyVaultAuthVal keyVaultAuthVal
	if err := json.Unmarshal([]byte(secret.Value), &hmacKeyVaultAuthVal); err != nil {
		return nil, err
	}
	return hmacKeyVaultAuthVal.Password, nil
}

type keyVaultAuthVal struct {
	Password []byte `json:"Password"`
}
