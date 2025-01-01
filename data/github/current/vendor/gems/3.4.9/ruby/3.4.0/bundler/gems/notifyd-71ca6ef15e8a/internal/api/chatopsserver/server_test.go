package chatopsserver

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func Test_BuildChatopsServer(t *testing.T) {
	cfg := Config{
		Addr:    ":8082",
		BaseURL: "http://localhost:8082",
		BotPublicKey: `
-----BEGIN PUBLIC KEY-----
MIIBCgKCAQEA1ZlW6Pz4mJqz4o534AESFAWEf564faea4J2n2Gzk+nra4wn4jnw2
SwpZdFla6w5a56e4AEWfySEPVKgoYr5CPv8qZPnuFTeFcERzI/xW54ymVPjq/zA/
m7jEW+Gqc5Pu0ObFq954aweWEAFGx48Jfy03Oao8jQFlQqQPfBVwVQxtjb4v+4Xk
zxaae6faedfv+695aew+6f95f45a454fae5fd4aefaefSLmXCZttB3XTpqBhsjWe
pCQuOAJC4HInBtLaefaeAWWFRawefawef6awef6ApWqqB+DtsoKg1GsBLdhvatxN
k863YIezcOyLhHdPoyHuzjfedqcvraOLlQIDAQAB
-----END PUBLIC KEY-----
`,
	}
	handler, err := NewChatopsHandler(cfg, logs.NullTelem, nil)
	require.NoError(t, err)
	srv := httptest.NewServer(NewChatopsServer(handler))
	defer srv.Close()
	require.NotNil(t, srv.URL)
	ctx := context.Background()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL+"/", http.NoBody)
	require.NoError(t, err)
	resp, err := srv.Client().Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	require.Equal(t, "max-age=31536000", resp.Header.Get("Strict-Transport-Security"), "expected HSTS header")
	require.Equal(t, "default-src 'none'; sandbox", resp.Header.Get("Content-Security-Policy"), "expected CSP header")
}

func Test_NewChatopsHandler(t *testing.T) {
	r := require.New(t)
	cfg := Config{}

	t.Run("returns rerror with missing env", func(t *testing.T) {
		// Test with missing Bot Public Key
		_, err := NewChatopsHandler(cfg, logs.NullTelem, nil)
		r.Equal("CHATOPS_BOT_PUBLIC_KEY is empty", err.Error())

		// Test with missing ChatopsBaseUrl but present PublicKey
		// should not happen, because BaseUrl is set as default
		cfg.BaseURL = ""
		cfg.BotPublicKey = "test"
		_, err = NewChatopsHandler(cfg, logs.NullTelem, nil)
		r.Equal("prefix must be a full url: 'https://{host}/{path}'", err.Error())
	})

	t.Run("returns rerror with failing parameters", func(t *testing.T) {
		// Test with ChatopsBaseUrl but wrong Public Key
		cfg.BaseURL = "http://localhost:8888/"
		cfg.BotPublicKey = "test"
		_, err := NewChatopsHandler(cfg, logs.NullTelem, nil)
		r.Equal("pem decoding failed", err.Error())

		// Test with ChatopsBaseUrl but not RSA Public Key
		// Public Key was generated for this test and is not used anywhere!
		cfg.BaseURL = "http://localhost:8888/"
		cfg.BotPublicKey = `
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAlRuRnThUjU8/prwYxbty
WPT9pURI3lbsKMiB6Fn/VHOKE13p4D8xgOCADpdRagdT6n4etr9atzDKUSvpMtR3
CP5noNc97WiNCggBjVWhs7szEe8ugyqF23XwpHQ6uV1LKH50m92MbOWfCtjU9p/x
qhNpQQ1AZhqNy5Gevap5k8XzRmjSldNAFZMY7Yv3Gi+nyCwGwpVtBUwhuLzgNFK/
yDtw2WcWmUU7NuC8Q6Maewfgawe6584efawetfaww75aGOBkhAX0LpKAEhKidixY
nP9PNVBvxgu3XZ4P36gZV6+ummKdBVnc3NqwBLu5+CcdRdusmHPHd5pHf4/38Z3/
6qU2a/fPvWzceVTEgZ47QjFMTCTmCwNt29cvi7zZeQzjtwQgn4ipN9NibRH/Ax/q
TbIzHfrJ1xa2RteWSdFjwtxi9C20HUkjXSeI4YlzQMH0fPX6KCE7aVePTOnB69I/
a9/q96DiXZajwlpq3wFctrs1oXqBp5DVrCIj8hU2wNgB7LtQ1mCtsYz//heai0K9
PhE4X6hiE0YmeAZjR0uHl8M/5aW9xCoJ72+12kKpWAa0SFRWLy6FejNYCYpkupVJ
yecLk/4L1W0l6jQQZnWErXZYe0PNFcmwGXy1Rep83kfBRNKRy5tvocalLlwXLdUk
AIU+2GKjyT3iMuzZxxFxPFMCAwEAAQ==
-----END PUBLIC KEY-----`
		_, err = NewChatopsHandler(cfg, logs.NullTelem, nil)
		r.Equal("x509: failed to parse public key (use ParsePKIXPublicKey instead for this key format)", err.Error())
	})

	t.Run("success with passing parameters", func(t *testing.T) {
		// Test with working Data
		// RSA Public Key was generated for this test and is not used anywhere!
		cfg.BaseURL = "http://localhost:8888/"
		cfg.BotPublicKey = `
-----BEGIN PUBLIC KEY-----
MIIBCgKCAQEA1ZlW6Pz4mJqz4o534AESFAWEf564faea4J2n2Gzk+nra4wn4jnw2
SwpZdFla6w5a56e4AEWfySEPVKgoYr5CPv8qZPnuFTeFcERzI/xW54ymVPjq/zA/
m7jEW+Gqc5Pu0ObFq954aweWEAFGx48Jfy03Oao8jQFlQqQPfBVwVQxtjb4v+4Xk
zxaae6faedfv+695aew+6f95f45a454fae5fd4aefaefSLmXCZttB3XTpqBhsjWe
pCQuOAJC4HInBtLaefaeAWWFRawefawef6awef6ApWqqB+DtsoKg1GsBLdhvatxN
k863YIezcOyLhHdPoyHuzjfedqcvraOLlQIDAQAB
-----END PUBLIC KEY-----
`
		_, err := NewChatopsHandler(cfg, logs.NullTelem, nil)
		r.NoError(err)
	})
}
