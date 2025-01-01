//go:build integration

package transport

import (
	"bytes"
	"context"
	"net/http"
	"testing"

	"github.com/github/go-auth/bodyhmac"
	"github.com/github/go-http/v2/middleware/headers"
	twcauth "github.com/github/go-twirp/v2/client/auth"
	"github.com/github/trust-metadata-api/pkg/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/testing/data"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
)

var createPkgAttReq = func(t *testing.T) *rpc.CreatePackageAttestationRequest {
	return &rpc.CreatePackageAttestationRequest{
		Purl:   TestPurl,
		Bundle: data.SigstoreBundle(t),
	}
}

/*
  Package Info Write API
	  POST /twirp/github.trust_metadata_api.PackageInfoWriteAPI/CreatePackageAttestation
*/

// PackageInfoWriteAPI/CreatePackageAttestation
// after publishing an attestation, ensure it exists in the database
func TestPackageInfoWriteAPIPublishingAttestation(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	// Create the attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)

	_, err := twClientWrite.CreatePackageAttestation(ctx, createPkgAttReq(t))
	assert.NoError(t, err)

	// Get the attestation
	req := &rpc.GetPackageAttestationsRequest{Purl: TestPurl}
	clientRead, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClientRead := rpc.NewPackageInfoReadAPIJSONClient(server.URL, clientRead)
	ctx = createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)

	resp, err := twClientRead.GetPackageAttestations(ctx, req)

	assert.NoError(t, err)
	assert.Len(t, resp.Attestations, 1, "should have one record")
}

func TestPackageInfoWrite_BadHMACClientID(t *testing.T) {
	testcases := []struct{ name, hmacClientID string }{
		{
			name:         "unknown HMAC client ID",
			hmacClientID: "unknown-client-id",
		},
		{
			name:         "GitHub service HMAC client ID",
			hmacClientID: testHMACConfig.Dotcom[0].ClientID,
		},
	}

	for _, tc := range testcases {
		server, _, cleanUp := newServerWithDB(t)

		// Create the attestation
		clientWrite, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
		twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)

		ctx := createCtxWithHMACClientIDHeader(t, tc.hmacClientID)

		_, err := twClientWrite.CreatePackageAttestation(ctx, createPkgAttReq(t))
		var twirpErr twirp.Error
		assert.ErrorAs(t, err, &twirpErr)
		assert.Equal(t, twirp.Unauthenticated, twirpErr.Code())

		cleanUp(t)
	}
}

// PackageInfoWriteAPI/CreatePackageAttestation
// Twirp Status Test: We should get a 200 when successfully creating an attestation
func TestTwirpStatusCodePackageInfoWriteAPICreatePackageAttestation(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)
	client := server.Client()
	endpoint := "/twirp/github.trust_metadata_api.PackageInfoWriteAPI/CreatePackageAttestation"

	req, _ := http.NewRequest("POST", server.URL+endpoint, bytes.NewBuffer(data.TwirpRequestRaw))
	req.Header.Set("Content-Type", "application/json")
	hmac, err := bodyhmac.CreateHeader(data.TwirpRequestRaw, []byte(testHMACConfig.PkgWrite[0].Keys[0]))
	assert.NoError(t, err)
	req.Header.Set(headers.RequestBodyHMAC, hmac)
	req.Header.Set(auth.HMACClientHeader, testHMACConfig.PkgWrite[0].ClientID)
	resp, err := client.Do(req)

	assert.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
}

/*
  TMA HMAC: Write
*/
// TMA HMAC: Write errors when the HMAC is missing
func TestHMACWriteMissingShouldError(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	twClient := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, http.DefaultClient)
	_, err := twClient.CreatePackageAttestation(context.Background(), createPkgAttReq(t))

	assert.Error(t, err, "should error when the HMAC is missing")
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), "should error with Unauthenticated")
}

// TMA HMAC: Write works when the body HMAC is present and valid
func TestBodyHMACWritePresentAndValid(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, client)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)
	_, err := twClient.CreatePackageAttestation(ctx, createPkgAttReq(t))

	assert.NoError(t, err)
}

func TestCreatePackageAttestation_BadHMACKey(t *testing.T) {
	testcases := []struct {
		name string
		key  string
	}{
		{
			name: "with invalid key",
			key:  "invalid hmac",
		},
		{
			name: "with read service HMAC key",
			key:  testHMACConfig.PkgRead[0].Keys[0],
		},
	}

	for _, tc := range testcases {
		server, _, cleanUp := newServerWithDB(t)

		client, _ := twcauth.NewBodyHMACSigner(tc.key, http.DefaultClient)
		twClient := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, client)
		ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)
		_, err := twClient.CreatePackageAttestation(ctx, createPkgAttReq(t))

		assert.Error(t, err, tc.name)
		var twirpErr twirp.Error
		assert.ErrorAs(t, err, &twirpErr, tc.name)
		assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), "should return an Unauthenticated error", tc.name)

		cleanUp(t)
	}
}
