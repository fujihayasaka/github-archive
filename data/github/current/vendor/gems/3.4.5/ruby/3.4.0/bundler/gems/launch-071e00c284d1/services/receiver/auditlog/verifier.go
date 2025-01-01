package auditlog

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"

	"github.com/pkg/errors"

	"github.com/github/launch/auth"
)

var signatureHeaderRegex = regexp.MustCompile(`(?i)HMAC-SHA512 Signature=([\S]+)`)

const (
	primaryHMACKeyName   = "ActionsAuthHmacKeyPrimary"
	secondaryHMACKeyName = "ActionsAuthHmacKeySecondary"
)

func (s *Service) verifyRequestSignature(ctx context.Context, req *http.Request, payload []byte) error {
	sig, err := s.getSignature(req)
	if err != nil {
		return err
	}

	url := s.buildSignatureURL(req)
	ok, err := s.verifySignature(ctx, sig, url, payload)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("Invalid signature")
	}

	return nil
}

func (s *Service) getSignature(req *http.Request) ([]byte, error) {
	matches := signatureHeaderRegex.FindStringSubmatch(req.Header.Get("Authorization"))
	if len(matches) < 2 {
		return nil, errors.New("Authorization header not found or invalid")
	}

	signature, err := base64.StdEncoding.DecodeString(matches[1])
	if err != nil {
		return nil, err
	}

	return signature, nil
}

func (s *Service) verifySignature(ctx context.Context, sig []byte, uri string, payload []byte) (bool, error) {
	var msg bytes.Buffer
	_, _ = msg.Write([]byte(uri))
	_, _ = msg.Write([]byte("\n"))
	_, _ = msg.Write(payload)
	data := msg.Bytes()

	// Try with the first secret
	primaryKey, err := s.getPrimaryHMACKey(ctx)
	if err != nil {
		s.obs.Debug(ctx, errors.Wrap(err, "getting primary hmac key").Error())
	} else if s.verifyWithKey(sig, data, primaryKey) {
		return true, nil
	}

	// Otherwise fall back to the second secret
	secondaryKey, err := s.getSecondaryHMACKey(ctx)
	if err != nil {
		e := errors.Wrap(err, "getting secondary hmac key")
		s.obs.Error(ctx, e.Error())
		return false, e
	}

	return s.verifyWithKey(sig, data, secondaryKey), nil
}

func (s *Service) verifyWithKey(sig, payload, key []byte) bool {
	return s.verifier.Verify(auth.NewSignature(sig), payload, auth.NewKey(key))
}

func (s *Service) buildSignatureURL(req *http.Request) string {
	var scheme string
	if s.cfg.IsDevelopment || s.cfg.IsEnterprise {
		scheme = "http"
	} else {
		scheme = "https"
	}

	return fmt.Sprintf("%s://%s%s", scheme, req.Host, req.URL.RequestURI())
}

func (s *Service) getPrimaryHMACKey(ctx context.Context) ([]byte, error) {
	// in enterprise mode, the hmac key should be defined in the configuration
	if s.cfg.IsEnterprise {
		return s.decodeKeyFromConfig(ctx, s.cfg.ActionsAuthHmacKeyPrimary, "ActionsAuthHmacKeyPrimary")
	}

	// In Codespaces, the hmac key should be defined in the configuration
	// In bp-dev, the hmac key should be defined in KeyVault
	if s.cfg.IsDevelopment && s.cfg.ActionsAuthHmacKeyPrimary != "" {
		return s.decodeKeyFromConfig(ctx, s.cfg.ActionsAuthHmacKeyPrimary, "ActionsAuthHmacKeyPrimary")
	}

	s.obs.Debug(ctx, "Using KeyVault value for ActionsAuthHmacKeyPrimary")
	secret, err := s.keyVaultClient.GetSecret(ctx, s.vaultName, primaryHMACKeyName)
	if err != nil {
		return nil, errors.Wrapf(err, "fetching %s", primaryHMACKeyName)
	}

	var primaryKey keyVaultAuthVal
	if err := json.Unmarshal([]byte(secret.Value), &primaryKey); err != nil {
		return nil, errors.Wrapf(err, "decoding %s", primaryHMACKeyName)
	}

	return primaryKey.Password, nil
}

func (s *Service) getSecondaryHMACKey(ctx context.Context) ([]byte, error) {
	// in enterprise mode, the hmac key should be defined in the configuration
	if s.cfg.IsEnterprise {
		return s.decodeKeyFromConfig(ctx, s.cfg.ActionsAuthHmacKeySecondary, "ActionsAuthHmacKeySecondary")
	}

	s.obs.Debug(ctx, "Using KeyVault value for ActionsAuthHmacKeySecondary")
	secret, err := s.keyVaultClient.GetSecret(ctx, s.vaultName, secondaryHMACKeyName)
	if err != nil {
		return nil, errors.Wrapf(err, "fetching %s", secondaryHMACKeyName)
	}

	var secondaryKey keyVaultAuthVal
	if err := json.Unmarshal([]byte(secret.Value), &secondaryKey); err != nil {
		return nil, errors.Wrapf(err, "decoding %s", secondaryHMACKeyName)
	}

	return secondaryKey.Password, nil
}

type keyVaultAuthVal struct {
	Password []byte `json:"Password"`
}

func (s *Service) decodeKeyFromConfig(ctx context.Context, key, keyName string) ([]byte, error) {
	s.obs.Debug(ctx, fmt.Sprintf("Using config value for %s", keyName))
	if key == "" {
		return nil, fmt.Errorf("%s is not set in the configuration", keyName)
	}

	sKey, err := base64.StdEncoding.DecodeString(key)
	if err != nil {
		return nil, errors.Wrap(err, fmt.Sprintf("decoding %s", keyName))
	}

	return sKey, nil
}
