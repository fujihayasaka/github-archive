package crpc

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

// Signature holds the signature for a request.
type Signature struct {
	KeyID     string
	Signature []byte
}

// HeaderValue returns the signature formatted for use in an HTTP header.
func (s *Signature) HeaderValue() string {
	b64sig := strings.TrimRight(base64.StdEncoding.EncodeToString(s.Signature), "=")
	return fmt.Sprintf("Signature keyid=%s,signature=%s", s.KeyID, b64sig)
}

// SignatureHeader gets and parses the Chatops-Signature header on the http.Request.
// Chatops-Signature: Signature keyid="rsakey1",signature="<base64-encoded-signature>"
func SignatureHeader(r *http.Request) (*Signature, error) {
	return ParseSignature(r.Header.Get("Chatops-Signature"))
}

// ParseSignature parses the header formatted signature into a Signature.
func ParseSignature(sig string) (*Signature, error) {
	if len(sig) < 11 {
		return nil, fmt.Errorf("Missing signature header")
	}

	if sig[0:10] != "Signature " {
		return nil, fmt.Errorf("Invalid Signature Header: %q", sig)
	}

	s := &Signature{}
	for _, kvp := range strings.Split(sig[10:], ",") {
		pair := strings.SplitN(kvp, `=`, 2)
		if len(pair) != 2 {
			return nil, fmt.Errorf("Invalid param %q in signature header %q", kvp, sig[10:])
		}

		value := pair[1]
		switch pair[0] {
		case "keyid":
			s.KeyID = value
		case "signature":
			if l := len(value) % 4; l > 0 {
				value += strings.Repeat("=", 4-l)
			}
			sig, err := base64.StdEncoding.DecodeString(value)
			if err != nil {
				return nil, err
			}
			s.Signature = sig
		}
	}
	return s, nil
}

// URLHeaderSignatureInput builds a string for signing.
func URLHeaderSignatureInput(u *url.URL, head http.Header, body string) string {
	// https://example.com/_chatops\nabc123\n2017-05-11T19:15:23Z\n{"method": "foo"}
	s := fmt.Sprintf("%s\n%s\n%s\n%s",
		u.String(),
		head.Get("Chatops-Nonce"),
		head.Get("Chatops-Timestamp"),
		body,
	)
	return s
}

// Verify verifies the signature.
func Verify(key *rsa.PublicKey, input string, sig []byte) error {
	h := sha256.New()
	h.Write([]byte(input))
	return rsa.VerifyPKCS1v15(key, crypto.SHA256, h.Sum(nil), sig)
}

// Sign signs the input with the key.
func Sign(key *rsa.PrivateKey, input string) ([]byte, error) {
	h := sha256.New()
	h.Write([]byte(input))
	return rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, h.Sum(nil))
}
