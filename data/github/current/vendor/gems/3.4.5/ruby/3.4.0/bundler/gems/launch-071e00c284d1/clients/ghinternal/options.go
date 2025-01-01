package ghinternal

import (
	"crypto/hmac"
	"crypto/sha256"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"

	errs "github.com/pkg/errors"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/pkg/launchhttp"
)

const hmacAlgorithm = "sha256"

// WithHMAC will set HMAC headers on requests, see:
// https://github.com/github/ce-engineering/blob/master/docs/api/Internal-API.md
func WithHMAC(key []byte) launchhttp.RequestOption {
	return withHMAC(key, time.Now)
}

func withHMAC(key []byte, getTimestamp func() time.Time) launchhttp.RequestOption {
	return func(r *http.Request) error {
		// HMAC for internal API: grab a current timestamp and hash it with our shared secret
		// then set the required header in the form {timestamp}.{hmac_hash}
		timestamp := getTimestamp().Unix()
		mac := hmac.New(sha256.New, key)
		_, err := mac.Write([]byte(strconv.Itoa(int(timestamp))))
		if err != nil {
			return errs.Wrap(err, "failed to generate request HMAC")
		}
		r.Header.Set("Request-HMAC", fmt.Sprintf("%d.%x", timestamp, mac.Sum(nil)))

		body, err := r.GetBody()
		if err != nil {
			return err
		}
		bytes, err := io.ReadAll(body)
		if err != nil {
			return err
		}

		mac = hmac.New(sha256.New, key)
		_, err = mac.Write(bytes)
		if err != nil {
			return errs.Wrap(err, "failed to generate content HMAC")
		}
		r.Header.Set("Content-HMAC", fmt.Sprintf("%s %x", hmacAlgorithm, mac.Sum(nil)))

		return nil
	}
}

func WithAccessToken(token *tokens.AccessToken) launchhttp.RequestOption {
	return func(r *http.Request) error {
		r.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token.Token))
		return nil
	}
}
