package jwt

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/pkg/errors"
)

// Provider provides a signed JWT
type Provider interface {
	Provide(ctx context.Context, requestURL, clientID, resource string) (signedJWT string, err error)
}

type provider struct {
	timeNow    func() time.Time
	trustSrc   func(ctx context.Context) (*rsa.PrivateKey, *x509.Certificate, error)
	jwtBuilder func(requestURL, clientID string, cert *x509.Certificate, timeNow func() time.Time) *jwt.Token
}

func (s *provider) Provide(ctx context.Context, requestURL, clientID, resource string) (string, error) {
	key, cert, err := s.trustSrc(ctx)
	if err != nil {
		return "", errors.Wrap(err, "obtaining key/cert combo")
	}
	jwt := s.jwtBuilder(requestURL, clientID, cert, s.timeNow)
	signed, err := jwt.SignedString(key)
	if err != nil {
		return "", errors.Wrap(err, "signing jwt")
	}

	data := getData(clientID, signed, resource)

	return data.Encode(), nil
}
