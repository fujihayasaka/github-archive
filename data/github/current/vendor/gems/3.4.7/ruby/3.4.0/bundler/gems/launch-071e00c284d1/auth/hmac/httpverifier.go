package hmac

import (
	"bytes"
	"context"
	"encoding/base64"
	"net/http"
	"regexp"

	"github.com/pkg/errors"

	"github.com/github/launch/auth"
	"github.com/github/launch/observability"
)

type HTTPVerifier struct {
	verifier    auth.Verifier
	obs         *observability.Observability
	keyFetcher  KeyFetcher
	httpsScheme string
}

func NewHTTPVerifier(
	keyFetcher KeyFetcher,
	obs *observability.Observability,
	verifier auth.Verifier,
	httpsScheme string,
) *HTTPVerifier {
	return &HTTPVerifier{
		obs:         obs,
		verifier:    verifier,
		keyFetcher:  keyFetcher,
		httpsScheme: httpsScheme,
	}
}

var signatureHeaderRegex = regexp.MustCompile(`(?i)HMAC-SHA512 Signature=([\S]+)`)

func (v *HTTPVerifier) Verify(ctx context.Context, req *http.Request, payload []byte) error {
	sig, err := getSignature(req)
	if err != nil {
		return err
	}
	url := v.buildSignatureURL(req)
	ok, err := v.verifySignature(ctx, sig, url, payload)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("invalid signature")
	}
	return nil
}

func getSignature(req *http.Request) ([]byte, error) {
	matches := signatureHeaderRegex.FindStringSubmatch(req.Header.Get("Authorization"))
	if len(matches) < 2 {
		return nil, errors.New("authorization header not found or invalid")
	}
	return base64.StdEncoding.DecodeString(matches[1])
}

func (v *HTTPVerifier) verifySignature(ctx context.Context, sig []byte, uri string, payload []byte) (bool, error) {
	keys, err := v.keyFetcher.GetHMACKeys(ctx)
	if err != nil {
		return false, err
	}
	var msg bytes.Buffer
	_, _ = msg.WriteString(uri)
	_, _ = msg.WriteRune('\n')
	_, _ = msg.Write(payload)
	data := msg.Bytes()

	// Try with the first secret
	if verifyWithKey(sig, data, keys[0], v.verifier) {
		return true, nil
	}

	// Otherwise fall back to the second secret
	return verifyWithKey(sig, data, keys[1], v.verifier), nil
}

func verifyWithKey(sig, payload, key []byte, verifier auth.Verifier) bool {
	return verifier.Verify(auth.NewSignature(sig), payload, auth.NewKey(key))
}

func (v *HTTPVerifier) buildSignatureURL(req *http.Request) string {
	// Shallow clone the request url and change the scheme.
	// If you switch to constructing a new url, watch out for double escaping (%20 => %2520).
	u := *req.URL
	u.Scheme = v.httpsScheme

	// the host is typically missing in request.URL.
	u.Host = req.Host

	// returns a url with an escaped path
	return u.String()
}
