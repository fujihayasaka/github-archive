package aqueduct

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"

	"github.com/twitchtv/twirp"
)

func newAuthInterceptor(auth authConfig) twirp.Interceptor {
	return func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req interface{}) (interface{}, error) {
			if auth.apiKey == "" {
				return next(ctx, req)
			}

			expiration := auth.clock().Unix() + int64(auth.tokenExpiration.Seconds())
			token := formatToken(expiration, auth.apiKeyVersion)
			signature := computeHmac([]byte(token), auth.apiKey)
			header := make(http.Header)
			header.Set("Authorization", fmt.Sprintf("HMAC-256 %s:%s", token, signature))
			if auth.authAs != "" {
				header.Set("X-Auth-As", auth.authAs)
			}
			ctx, err := twirp.WithHTTPRequestHeaders(ctx, header)
			if err != nil {
				return nil, err
			}

			return next(ctx, req)
		}
	}
}

func formatToken(expiration int64, version *int) string {
	if version == nil {
		return fmt.Sprintf("%d", expiration)
	}
	return fmt.Sprintf("%d:%d", expiration, *version)
}

func computeHmac(data []byte, secret string) string {
	h := hmac.New(sha256.New, []byte(secret))
	h.Write(data)
	return hex.EncodeToString(h.Sum(nil))
}
