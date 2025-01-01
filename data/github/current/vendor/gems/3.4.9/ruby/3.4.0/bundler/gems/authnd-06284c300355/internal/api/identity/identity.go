package identity

import (
	"context"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/x509"
	"encoding/base64"
	"encoding/binary"
	"encoding/pem"
	"fmt"
	"math/big"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/twitchtv/twirp"
)

const (
	Issuer         = "https://github.com/login/oauth"
	AddToNowForNBF = -time.Minute * 5
	AddToNowForEXP = time.Hour * 6
)

// Manager is a struct that contains the methods for managing identity
type Manager struct {
	privateKey *privateKey
	publicKeys []*publicKey
}

type privateKey struct {
	keyID string
	x5t   string
	key   *rsa.PrivateKey
}

type publicKey struct {
	key *rsa.PublicKey

	// Fields for JWKS.  These are precomputed for performance.
	keyID string
	n     string
	e     string
	x5c   string
	x5t   string
}

type RawPublicKey struct {
	// Key in StdBase64 encoded PKIX ASN.1 DER format
	PublicKey string

	// Certificate in PEM block
	Certificate string
}

type RawPrivateKey struct {
	// Key in PEM block
	PrivateKey string

	// Certificate in PEM block
	Certificate string
}

func newManager(privKey *RawPrivateKey, pubKeys []*RawPublicKey) (*Manager, error) {
	privateKeyBytes := []byte(privKey.PrivateKey)

	// Parse privatekey as RSA private key type
	privateKeyRSA, err := parseRSAPrivateKey(privateKeyBytes)
	if err != nil {
		return nil, err
	}

	_, privateKeyThumbprint, err := parseCertificate(privKey.Certificate)
	if err != nil {
		return nil, err
	}

	privateKeyWithID := &privateKey{
		keyID: generateKeyID(&privateKeyRSA.PublicKey),
		key:   privateKeyRSA,
		x5t:   base64.RawURLEncoding.EncodeToString(privateKeyThumbprint),
	}

	if len(pubKeys) == 0 {
		return nil, fmt.Errorf("no public keys provided")
	}
	publicKeysWithIDs := make([]*publicKey, len(pubKeys))
	foundPrivateKeyID := false
	for i, key := range pubKeys {
		// Parse publickey as RSA public key type
		publicKeyRSA, err := parseRSAPublicKey(key.PublicKey)
		if err != nil {
			return nil, err
		}

		keyID := generateKeyID(publicKeyRSA)
		if keyID == privateKeyWithID.keyID {
			foundPrivateKeyID = true
		}

		exponentBytes := make([]byte, 8)
		binary.BigEndian.PutUint64(exponentBytes, uint64(publicKeyRSA.E))
		j := 0
		for ; j < len(exponentBytes); j++ {
			if exponentBytes[j] != 0x0 {
				break
			}
		}

		cert, thumbprint, err := parseCertificate(key.Certificate)
		if err != nil {
			return nil, err
		}

		publicKeysWithIDs[i] = &publicKey{
			key: publicKeyRSA,

			keyID: keyID,
			n:     base64.RawURLEncoding.EncodeToString(publicKeyRSA.N.Bytes()),
			e:     base64.RawURLEncoding.EncodeToString(exponentBytes[j:]),

			// For whatever reason, the x5c field is standard encoding.
			x5c: base64.StdEncoding.EncodeToString(cert.Raw),
			x5t: base64.RawURLEncoding.EncodeToString(thumbprint),
		}
	}

	if !foundPrivateKeyID {
		return nil, fmt.Errorf("no public key found which shares an id with the private key.  Signed tokens will not be verifiable")
	}

	return &Manager{
		privateKey: privateKeyWithID,
		publicKeys: publicKeysWithIDs,
	}, nil
}

// NewManagerServer creates a new identity manager server.
func NewManagerServer(privKey *RawPrivateKey, pubKeys []*RawPublicKey, hooks *twirp.ServerHooks) (pb.TwirpServer, error) {
	manager, err := newManager(privKey, pubKeys)
	if err != nil {
		return nil, err
	}
	return pb.NewIdentityManagerServer(manager, hooks), nil
}

// IssueIdentityToken issues an identity token.
func (m *Manager) IssueIdentityToken(ctx context.Context, req *pb.IssueIdentityTokenRequest) (*pb.IssueIdentityTokenResponse, error) {
	claimsMap := make(jwt.MapClaims)
	claimsMap["sub"] = req.Claims.Sub
	claimsMap["aud"] = req.Claims.Aud

	claimsMap["act"] = jwt.MapClaims{
		"sub": req.Claims.Act.Sub,
	}

	unsignedToken := m.buildToken(claimsMap)
	signedToken, err := unsignedToken.SignedString(m.privateKey.key)
	if err != nil {
		return nil, twirp.InternalError("failed to sign token")
	}

	return &pb.IssueIdentityTokenResponse{
		Token: signedToken,
	}, nil
}

func (m *Manager) DiscoveryDocument(ctx context.Context, req *pb.DiscoveryDocumentRequest) (*pb.DiscoveryDocumentResponse, error) {
	return &pb.DiscoveryDocumentResponse{
		Claims:     []string{"sub", "aud", "exp", "nbf", "iat", "iss", "act"},
		Algorithms: []string{"RS256"},
		Scopes:     []string{"openid"},
	}, nil
}

func (m *Manager) Jwks(ctx context.Context, req *pb.JwksRequest) (*pb.JwksResponse, error) {
	keys := make([]*pb.PublicKey, len(m.publicKeys))
	for i, publicKey := range m.publicKeys {
		keys[i] = &pb.PublicKey{
			Kty: "RSA",
			Alg: "RS256",
			Use: "sig",
			Kid: publicKey.keyID,
			N:   publicKey.n,
			E:   publicKey.e,
			X5C: []string{publicKey.x5c},
			X5T: publicKey.x5t,
		}
	}

	return &pb.JwksResponse{
		Keys: keys,
	}, nil

}

func (m *Manager) buildToken(claimsMap jwt.MapClaims) *jwt.Token {
	// Issuer
	claimsMap["iss"] = Issuer
	// Issued At
	claimsMap["iat"] = jwt.NewNumericDate(time.Now())
	// Not Before
	claimsMap["nbf"] = jwt.NewNumericDate(time.Now().Add(AddToNowForNBF))
	// Expires At (same as tokenz default, 6 hours)
	claimsMap["exp"] = jwt.NewNumericDate(time.Now().Add(AddToNowForEXP))

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claimsMap)
	token.Header["kid"] = m.privateKey.keyID

	if m.privateKey.x5t != "" {
		token.Header["x5t"] = m.privateKey.x5t
	}

	return token
}

func parseRSAPrivateKey(content []byte) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode(content)
	if block == nil {
		return nil, fmt.Errorf("failed to decode private key PEM block")
	}

	key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("error parsing private key: %w", err)
	}

	return key, nil
}

func parseRSAPublicKey(content string) (*rsa.PublicKey, error) {
	bytes, err := base64.StdEncoding.DecodeString(content)
	if err != nil {
		return nil, fmt.Errorf("error parsing public key as base64: %w", err)
	}

	key, err := x509.ParsePKIXPublicKey(bytes)
	if err != nil {
		return nil, fmt.Errorf("error parsing public key: %w", err)
	}

	rsaKey, ok := key.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("failed to parse public key as RSA public key")
	}

	return rsaKey, nil
}

func generateKeyID(key *rsa.PublicKey) string {
	bytes := append(key.N.Bytes(), big.NewInt(int64(key.E)).Bytes()...)
	return uuid.NewSHA1(uuid.Nil, bytes).String()
}

func parseCertificate(content string) (*x509.Certificate, []byte, error) {
	block, _ := pem.Decode([]byte(content))
	if block == nil {
		return nil, nil, fmt.Errorf("failed to decode certificate PEM block")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, nil, fmt.Errorf("error parsing certificate: %w", err)
	}

	thumbprint := sha1.Sum(cert.Raw)

	return cert, thumbprint[:], nil
}
