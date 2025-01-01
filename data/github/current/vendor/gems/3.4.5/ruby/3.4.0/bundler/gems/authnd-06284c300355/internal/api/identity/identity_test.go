package identity

import (
	"context"
	"fmt"
	"testing"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/golang-jwt/jwt/v5"
)

const (
	rsaPrivateKey = `-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAttLhv5V+UzfV6hnvSiNpyP+xGGINNNAgit88DwapfS5ooxGp
zOvHVQ6mxqxIAHevWLlFKEVAAmHCEOVHtsfziS313fyONLqH62Cp39uGwT1z/c2E
OEmCgn/roXjTm3oBW0qvvufagOxOvkEfAkDbThxn+wgENmqHMWy6VFLnucSeowlC
KgZbc/7XgCZBdRCjOjoO4QUJLxZrBx24Mxlzz0uGRv8uGSRw8EarBh1idWgtjUxB
porGaATJJa2FXEx+Zt6ul2ZOO3x+L2htNYeHOH7jo8e9s6ptdJYfjnKVai3a6VAo
sJ1QfGashemql/1Af3akVrqQDtY4QASzIoelWQIDAQABAoIBAQCqUsz+L8gAv4QL
FR5Zc6SaHZxfmvmyujOXLWJGnW5JsXLKeSo4P3D1TTES5m4uAVLa1cAYRGvdzDWA
iBrHroC0zJzCswfJF/6IywV4CI0Cer4VNeJ4jgOIkKR1SpvZvVCGPI5+zIJEmeLC
XOkGsGWf39b/h/hkudo5sZHl/VblOTRfbZlak+1nHiyJVipic7bipwXhy0ABjvcI
HIXT71DFfSnfi1e9wd+XqTveKwhREtcQMEn/JMUyn0gL9ACRhbGTeDGQsGjQBXC0
7RsFLY3gTlK2HuKJmbOKcPlhQ1EuV8n9eSNtvOe0Ue7bEPdQjPE/LoaFVr3VkcnM
4Ltf5moBAoGBAOjhcng4mVnp+wujollZVexbn3tPCtcMFifx8JY4ljMxUBYYtgzn
/hKYmyWDSSsnrkiIoYp6aOtr4Vm6miRgDlviCiPVUfThTrJbFx4gIVS8x5719709
hXa5+PDUGrwuU4AgozvYxg+CYlAfAXSM+S9YAxC7cABjbiPden0Zw/TTAoGBAMj5
QxiIlPSt7KLoT6GQmd7CTWROA7bpx/DfbPCrIOJ5soS5EIuvs2TxqY+tVSDHcLye
qlZepzQ+zZZqSYgj7mx5693oT2lzekVpqP2QiHcfBN/DVyTJWMQg993hRFD5qyiD
srDW5nWiS5fJHyT/MN91rLW8tiddyil0m+MdBFGjAoGBAMDTk83Zx5h8tgMQLehf
oVbBEs+uRiKD/oB6wyQPnMasqUxyj6MmIOlS9PvdtiMGizfB8khQTTnJrOF4MhO2
eY05H/5FrsPeHyRtajnmjtK0MXH85nIKU81X9bmrVqvEjB1GaQKv3mePJUqEMddI
tzetX3RmTznzGoqV48tcHzZDAoGALGBVv2oRMgHheYtAYhVy1Gwk+Jv9V/tBCd/b
xzySM0/Z6lKO47k1LHnsDeyhGm7PZubGB/I4i2G+tZLcj7IXaF53hXVRa6BzBDaz
eOHcMClqQxp3+Ih5ED2TXavrENJAR97kqwWYt6rRdD+Vn+61VPI/45U6x3B/Pi4g
acKzfG8CgYEA4XR1+0g1w0CiuVswwH/gBLscS9ywUBk+0+ef3gHEX1eLlxvpEIJh
ytmx5nenvBfWI4XkJlwplAgIV3fhkyw/lyJTrX4y65rA520iYMUl4mC4qkEzzzCP
1scBDePxLMOUHmGZtPX0KbSdQMLCpe0lhiOklprLwo11DTP0AB7F2Io=
-----END RSA PRIVATE KEY-----`

	rsaPublicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAttLhv5V+UzfV6hnvSiNpyP+xGGINNNAgit88DwapfS5ooxGpzOvHVQ6mxqxIAHevWLlFKEVAAmHCEOVHtsfziS313fyONLqH62Cp39uGwT1z/c2EOEmCgn/roXjTm3oBW0qvvufagOxOvkEfAkDbThxn+wgENmqHMWy6VFLnucSeowlCKgZbc/7XgCZBdRCjOjoO4QUJLxZrBx24Mxlzz0uGRv8uGSRw8EarBh1idWgtjUxBporGaATJJa2FXEx+Zt6ul2ZOO3x+L2htNYeHOH7jo8e9s6ptdJYfjnKVai3a6VAosJ1QfGashemql/1Af3akVrqQDtY4QASzIoelWQIDAQAB"

	rsaCertificate = `-----BEGIN CERTIFICATE-----
MIIC6jCCAdKgAwIBAgIBATANBgkqhkiG9w0BAQsFADAdMRswGQYDVQQKExJzZWxm
LXNpZ25lZC5naXRodWIwHhcNMjQxMTE4MTk1ODIzWhcNMzQxMTE2MTk1ODIzWjAd
MRswGQYDVQQKExJzZWxmLXNpZ25lZC5naXRodWIwggEiMA0GCSqGSIb3DQEBAQUA
A4IBDwAwggEKAoIBAQC20uG/lX5TN9XqGe9KI2nI/7EYYg000CCK3zwPBql9Lmij
EanM68dVDqbGrEgAd69YuUUoRUACYcIQ5Ue2x/OJLfXd/I40uofrYKnf24bBPXP9
zYQ4SYKCf+uheNObegFbSq++59qA7E6+QR8CQNtOHGf7CAQ2aocxbLpUUue5xJ6j
CUIqBltz/teAJkF1EKM6Og7hBQkvFmsHHbgzGXPPS4ZG/y4ZJHDwRqsGHWJ1aC2N
TEGmisZoBMklrYVcTH5m3q6XZk47fH4vaG01h4c4fuOjx72zqm10lh+OcpVqLdrp
UCiwnVB8ZqyF6aqX/UB/dqRWupAO1jhABLMih6VZAgMBAAGjNTAzMA4GA1UdDwEB
/wQEAwICpDATBgNVHSUEDDAKBggrBgEFBQcDATAMBgNVHRMBAf8EAjAAMA0GCSqG
SIb3DQEBCwUAA4IBAQCth5ID5I2QtZd33bwjrxPV3uPo1Tm3th/3U0Bv06gjXLqJ
V/FrzWcPrPNNO/fuwTi10Y0N5GbmH3+ycNM13fNkbjAN91LBtO6lCYbdNDH+svSz
zm483OX0Dw6VaSpBOpFdH8K8iJSbUNTjIUjYGW30Jx/qdcZQ7O76xcWRonTzdFmO
FUeg7ekdAsSEux5rVPS8kJx1fSVTwq1z2hZWjoaWmRJjKxnLzIKDx60cMqu+Io/r
kw/e/RdHIXuHhO2VM7Qd3KicKn9M1vFvdFgAsAPTP+GHMBmDvutrf1ZjjmFMt8tT
Mv5G4wycVRKedVObrQXP2fGK0pqLYUUh+jUrk5JA
-----END CERTIFICATE-----`
)

func TestNewManagerServer(t *testing.T) {
	privateKey := &RawPrivateKey{PrivateKey: rsaPrivateKey, Certificate: rsaCertificate}
	publicKeys := []*RawPublicKey{{PublicKey: rsaPublicKey, Certificate: rsaCertificate}}
	_, err := NewManagerServer(privateKey, publicKeys, nil)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestManagerServer(t *testing.T) {
	privateKey := &RawPrivateKey{PrivateKey: rsaPrivateKey, Certificate: rsaCertificate}
	publicKeys := []*RawPublicKey{{PublicKey: rsaPublicKey, Certificate: rsaCertificate}}
	manager, err := newManager(privateKey, publicKeys)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}

	resp, err := manager.IssueIdentityToken(context.Background(), &pb.IssueIdentityTokenRequest{
		Claims: &pb.Claims{
			Sub: "sub",
			Aud: "aud",
			Act: &pb.ActorClaims{
				Sub: "act.sub",
			},
		},
	})
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}

	if resp.Token == "" {
		t.Errorf("expected token to not be empty")
	}

	token, err := jwt.Parse(resp.Token, func(token *jwt.Token) (any, error) {
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}

		return &manager.privateKey.key.PublicKey, nil
	})
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		t.Errorf("unexpected claims type: %T", token.Claims)
	}

	if sub, ok := claims["sub"].(string); !ok || sub != "sub" {
		t.Errorf("unexpected sub claim: %v", sub)
	}

	if aud, ok := claims["aud"].(string); !ok || aud != "aud" {
		t.Errorf("unexpected aud claim: %v", aud)
	}

	act, ok := claims["act"].(map[string]any)
	if !ok {
		t.Errorf("unexpected act claim type: %T", claims["act"])
	}
	if actSub, ok := act["sub"].(string); !ok || actSub != "act.sub" {
		t.Errorf("unexpected act.sub claim: %v", actSub)
	}

	if iss, ok := claims["iss"].(string); !ok || iss != "https://github.com/login/oauth" {
		t.Errorf("unexpected iss claim: %v", iss)
	}

	if _, ok := claims["iat"]; !ok {
		t.Errorf("missing iat claim")
	}

	if _, ok := claims["nbf"]; !ok {
		t.Errorf("missing nbf claim")
	}

	if _, ok := claims["exp"]; !ok {
		t.Errorf("missing exp claim")
	}

	if kid, ok := token.Header["kid"].(string); !ok || kid != manager.privateKey.keyID {
		t.Errorf("unexpected kid header: %v", kid)
	}

	if x5t, ok := token.Header["x5t"].(string); !ok || x5t != manager.privateKey.x5t {
		t.Errorf("unexpected x5t header: %v", x5t)
	}
}

func TestDiscoveryDocument(t *testing.T) {
	privateKey := &RawPrivateKey{PrivateKey: rsaPrivateKey, Certificate: rsaCertificate}
	publicKeys := []*RawPublicKey{{PublicKey: rsaPublicKey, Certificate: rsaCertificate}}
	manager, err := newManager(privateKey, publicKeys)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}

	resp, err := manager.DiscoveryDocument(context.Background(), &pb.DiscoveryDocumentRequest{})
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}

	if len(resp.GetAlgorithms()) != 1 || resp.GetAlgorithms()[0] != "RS256" {
		t.Errorf("wrong algorithms found")
	}

	if len(resp.GetScopes()) != 1 || resp.GetScopes()[0] != "openid" {
		t.Errorf("wrong scopes found")
	}

	if len(resp.GetClaims()) == 0 {
		t.Errorf("claims missing")
	}
}

func TestJwks(t *testing.T) {
	privateKey := &RawPrivateKey{PrivateKey: rsaPrivateKey, Certificate: rsaCertificate}
	publicKeys := []*RawPublicKey{{PublicKey: rsaPublicKey, Certificate: rsaCertificate}}
	manager, err := newManager(privateKey, publicKeys)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}

	resp, err := manager.Jwks(context.Background(), &pb.JwksRequest{})
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}

	if len(resp.GetKeys()) != 1 {
		t.Errorf("unexpected number of keys: %v", len(resp.GetKeys()))
	}

	key := resp.GetKeys()[0]
	if key.GetKty() != "RSA" {
		t.Errorf("unexpected kty: %v", key.GetKty())
	}

	if key.GetAlg() != "RS256" {
		t.Errorf("unexpected alg: %v", key.GetAlg())
	}

	if key.GetUse() != "sig" {
		t.Errorf("unexpected use: %v", key.GetUse())
	}

	if key.GetKid() != manager.privateKey.keyID {
		t.Errorf("unexpected kid: %v", key.GetKid())
	}

	if key.GetN() != manager.publicKeys[0].n {
		t.Errorf("unexpected n: %v", key.GetN())
	}

	if key.GetE() != manager.publicKeys[0].e {
		t.Errorf("unexpected e: %v", key.GetE())
	}
}
