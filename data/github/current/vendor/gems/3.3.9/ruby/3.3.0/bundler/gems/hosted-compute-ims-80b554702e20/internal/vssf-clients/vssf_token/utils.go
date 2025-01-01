package vssf_token

import (
	"crypto/rsa"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/pkg/errors"
)

func GetOAuthExchangeURL(baseURL string, targetServiceAppID string) (string, error) {
	return fmt.Sprintf("%s/_apis/oauth2/token/%s", baseURL, targetServiceAppID), nil
}

func GetGrantFormData(requestURL string, pem string, jwtDuration time.Duration, appID string) (url.Values, error) {
	jwtToken := getGrant(requestURL, jwtDuration, appID)
	privateKey, err := getPrivateKey(pem)
	if err != nil {
		return nil, errors.Wrap(err, "unable to get private key from PEM")
	}
	signed, err := jwtToken.SignedString(privateKey)
	if err != nil {
		return nil, errors.Wrap(err, "unable to sign JWT")
	}
	data := url.Values{}
	data.Set("grant_type", "client_credentials")
	data.Set("client_assertion", signed)
	data.Set("client_assertion_type", "urn:ietf:params:oauth:client-assertion-type:jwt-bearer")
	return data, nil
}

func getPrivateKey(pem string) (*rsa.PrivateKey, error) {
	key := unescapeConsulKVString(pem)
	privateKey, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(key))
	if err != nil {
		return nil, err
	}
	return privateKey, nil
}

func getGrant(requestURL string, jwtDuration time.Duration, appID string) *jwt.Token {
	now := time.Now()
	return jwt.NewWithClaims(
		jwt.SigningMethodRS256,
		jwt.MapClaims{
			"aud": requestURL,
			"exp": now.Add(jwtDuration).Unix(), // epoch seconds
			"nbf": now.Unix(),                  // epoch seconds
			"iss": appID,
			"sub": appID,
		},
	)
}

func unescapeConsulKVString(s string) string {
	return strings.ReplaceAll(s, "\\n", "\n")
}
