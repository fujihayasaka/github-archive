package chatops

import (
	"bytes"
	"crypto/rsa"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/github/go-chatops/v2"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/stretchr/testify/require"
)

func TestRunChatop(t *testing.T) {
	t.Run("good request", func(t *testing.T) {
		ns, err := NewNamespaceHandler("osstest")
		require.NoError(t, err)
		srv := buildServer(t, ns, "")

		_, err = ns.Register(pingChatop())
		require.NoError(t, err)

		res := sendCmd(t, srv.URL+"/_chatops", &chatops.CommandRequest{
			Method: "ping",
			User:   "bob",
			RoomID: "test",
		})
		require.Equal(t, "pong", res.Result)
	})

	t.Run("good request", func(t *testing.T) {
		ns, err := NewNamespaceHandler("osstest")
		require.NoError(t, err)
		srv := buildServer(t, ns, "")

		_, err = ns.Register(pingChatop())
		require.NoError(t, err)

		res := sendCmd(t, srv.URL+"/_chatops", &chatops.CommandRequest{
			Method: "random",
			User:   "bob",
			RoomID: "test",
		})
		require.Contains(t, res.Result, "No chatops method")
	})
}

func TestAuthKey(t *testing.T) {
	t.Setenv("CHATOPS_AUTH_PUBLIC_KEY", string(pubBytes(t)))
	t.Setenv("CHATOPS_AUTH_ALT_PUBLIC_KEY", string(pubBytes(t)))
	cfg, err := config.Load()
	require.NoError(t, err)

	t.Run("auth_key", func(t *testing.T) {
		c := &Chatops{
			AuthBaseURL:      cfg.ChatopsAuthBaseURL,
			HTTPAddr:         cfg.ChatopsHTTPAddr,
			HealthHTTPAddr:   cfg.ChatopsHealthHTTPAddr,
			AuthPublicKey:    []byte(cfg.ChatopsAuthPublicKey),
			AuthAltPublicKey: nil,
			Namespace:        Namespace,
			HMACSecret:       cfg.HMACSecret,
		}

		keys, err := c.authKey(c.AuthPublicKey, c.AuthAltPublicKey)
		require.NoError(t, err)
		require.Len(t, keys, 1)
	})

	t.Run("alt_auth_key", func(t *testing.T) {
		c := &Chatops{
			AuthBaseURL:      cfg.ChatopsAuthBaseURL,
			HTTPAddr:         cfg.ChatopsHTTPAddr,
			HealthHTTPAddr:   cfg.ChatopsHealthHTTPAddr,
			AuthPublicKey:    nil,
			AuthAltPublicKey: []byte(cfg.ChatopsAuthAltPublicKey),
			Namespace:        Namespace,
			HMACSecret:       cfg.HMACSecret,
		}

		keys, err := c.authKey(c.AuthPublicKey, c.AuthAltPublicKey)
		require.NoError(t, err)
		require.Len(t, keys, 1)
	})

	t.Run("both_auth_keys", func(t *testing.T) {
		c := &Chatops{
			AuthBaseURL:      cfg.ChatopsAuthBaseURL,
			HTTPAddr:         cfg.ChatopsHTTPAddr,
			HealthHTTPAddr:   cfg.ChatopsHealthHTTPAddr,
			AuthPublicKey:    []byte(cfg.ChatopsAuthPublicKey),
			AuthAltPublicKey: []byte(cfg.ChatopsAuthAltPublicKey),
			Namespace:        Namespace,
			HMACSecret:       cfg.HMACSecret,
		}

		keys, err := c.authKey(c.AuthPublicKey, c.AuthAltPublicKey)
		require.NoError(t, err)
		require.Len(t, keys, 2)
	})
}

func buildServer(t *testing.T, ns *chatops.Namespace, prefix string) *httptest.Server {
	mux := http.NewServeMux()
	srv := httptest.NewServer(mux)

	h, err := chatops.NewHandler(ns, srv.URL+prefix)
	if err != nil {
		t.Fatal(err)
	}
	h.AddBot(serverKey(t))

	h.Setup(mux)
	return srv
}

func sendCmd(t *testing.T, rawurl string, creq *chatops.CommandRequest) *chatops.CommandResponse {
	by, err := json.Marshal(creq)
	if err != nil {
		t.Fatal(err)
	}

	req, err := http.NewRequest(http.MethodPost, rawurl, bytes.NewReader(by))
	if err != nil {
		t.Fatal(err)
	}

	signBotRequest(t, botKey(t), req, string(by))

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}

	cres := &chatops.CommandResponse{}
	err = json.NewDecoder(res.Body).Decode(cres)
	_ = res.Body.Close()
	if err != nil {
		t.Fatal(err)
	}

	return cres
}

func signBotRequest(t *testing.T, key *rsa.PrivateKey, req *http.Request, body string) {
	sigBy, err := chatops.Sign(key, chatops.URLHeaderSignatureInput(req.URL, req.Header, body))
	if err != nil {
		t.Error(err)
	} else {
		sig := &chatops.Signature{KeyID: "test", Signature: sigBy}
		req.Header.Set("Chatops-Signature", sig.HeaderValue())
	}
}

func serverKey(t *testing.T) *rsa.PublicKey {
	pubkey, err := chatops.ReadPEMPublicKey(chatops.HubotTestPublicKey)
	if err != nil {
		t.Fatal(err)
	}
	return pubkey
}

func botKey(t *testing.T) *rsa.PrivateKey {
	privkey, err := chatops.ReadPEMPrivateKey(chatops.HubotTestPrivateKey)
	if err != nil {
		t.Fatal(err)
	}
	return privkey
}

func pubBytes(t *testing.T) []byte {
	t.Helper()
	pubBy, err := os.ReadFile("testdata/key.pub.pem")
	require.NoError(t, err)
	return pubBy
}
