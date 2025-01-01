package muhttp_test

import (
	"bytes"
	"context"
	"testing"

	"github.com/github/launch/pkg/mu/muhttp"
)

func TestHMACSignedRequest(t *testing.T) {
	ctx := context.Background()
	body := bytes.NewReader([]byte(`{"payload":true}`))
	req, err := muhttp.NewSignedRequest(ctx, "POST", "https://api.github.com/users/mu", "secret", body)
	if err != nil {
		t.Fatalf("error creating request: %s", err)
	}

	expected := "sha256 07e6b4c58c5fe376c3993c8f738b4dbd5598934544f7ff243bc75dc23bd8e1b3"
	sig := req.Header.Get("Content-HMAC")
	if sig != expected {
		t.Errorf("expected %q got %q", expected, sig)
	}
}

func TestHMACSignedRequestWithEmptyKey(t *testing.T) {
	ctx := context.Background()
	body := bytes.NewReader([]byte(`{"payload":true}`))

	_, err := muhttp.NewSignedRequest(ctx, "POST", "https://api.github.com/users/mu", "", body)
	if err == nil {
		t.Fatalf("expected error")
	}
}

func TestHMACSignedRequestWithNoBody(t *testing.T) {
	ctx := context.Background()

	_, err := muhttp.NewSignedRequest(ctx, "POST", "https://api.github.com/users/mu", "secret", nil)
	if err == nil {
		t.Fatalf("expected error")
	}
}
