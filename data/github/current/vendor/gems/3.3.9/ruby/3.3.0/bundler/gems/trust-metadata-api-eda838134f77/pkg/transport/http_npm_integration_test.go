//go:build integration

package transport

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/github/go-auth/bodyhmac"
	"github.com/github/go-http/v2/middleware/headers"
	twcauth "github.com/github/go-twirp/v2/client/auth"
	"github.com/github/trust-metadata-api/pkg/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	tmatesting "github.com/github/trust-metadata-api/testing"
	"github.com/github/trust-metadata-api/testing/data"
	v1 "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// fixtureNPM represents the protobuf rpc data used for testing NPM package attestations
type fixtureNPM struct {
	bundle          *v1.Bundle
	twirpRequestRaw []byte
	// PackageInfoReadAPI/GetPackageAttestations
	getReq                   *rpc.GetPackageAttestationsRequest
	getPkgReqWithOwnerRepoID *rpc.GetPackageAttestationsRequest
	// PackageInfoReadAPI/GetPackageProvenanceSummary
	getPkgProvenanceReq        *rpc.GetPackageProvenanceSummaryRequest
	getPkgProvenanceResp       *rpc.GetPackageProvenanceSummaryResponse
	getPkgSLSAV1ProvenanceResp *rpc.GetPackageProvenanceSummaryResponse
	// PackageInfoWriteAPI/CreatePackageAttestation
	createPkgAttReq                           *rpc.CreatePackageAttestationRequest
	createPkgAttReqSigstore100                *rpc.CreatePackageAttestationRequest
	createLinkPkgReq                          *rpc.CreatePackageAttestationRequest
	createSLSAV1ProvenancePkgReq              *rpc.CreatePackageAttestationRequest
	createPkgAttReqWithOwnerRepoID            *rpc.CreatePackageAttestationRequest
	createPkgAttReqSigstore100WithOwnerRepoID *rpc.CreatePackageAttestationRequest
}

// newNPMFixture constructs a new fixtureNPM
func newNPMFixture(t *testing.T) *fixtureNPM {
	ownerID, repoID := uint64(42), uint64(12345)
	expectedProvenanceSummary := newExpectedProvenanceSummaryPb()
	newExpectedSLSAV1ProvenanceSummary := newExpectedSLSAV1ProvenanceSummaryPb()

	return &fixtureNPM{
		bundle:          data.SigstoreBundle(t),
		twirpRequestRaw: data.TwirpRequestRaw,
		// PackageInfoReadAPI/GetPackageAttestations
		getReq: &rpc.GetPackageAttestationsRequest{
			Purl: TestPurl,
		},
		getPkgReqWithOwnerRepoID: &rpc.GetPackageAttestationsRequest{
			Purl:         TestPurl,
			OwnerId:      &ownerID,
			RepositoryId: &repoID,
		},
		// PackageInfoReadAPI/GetPackageProvenanceSummary
		getPkgProvenanceReq: &rpc.GetPackageProvenanceSummaryRequest{
			Purl: TestPurl,
		},
		getPkgProvenanceResp: &rpc.GetPackageProvenanceSummaryResponse{
			ProvenanceSummary: expectedProvenanceSummary,
		},
		// PackageInfoReadAPI/GetPackageProvenanceSummary
		getPkgSLSAV1ProvenanceResp: &rpc.GetPackageProvenanceSummaryResponse{
			ProvenanceSummary: newExpectedSLSAV1ProvenanceSummary,
		},
		// PackageInfoWriteAPI/CreatePackageAttestation
		createPkgAttReq: &rpc.CreatePackageAttestationRequest{
			Purl:   TestPurl,
			Bundle: data.SigstoreBundle(t),
		},
		createPkgAttReqSigstore100: &rpc.CreatePackageAttestationRequest{
			Purl:   TestPurl,
			Bundle: data.SigstoreJs100ProtoBundle(t),
		},
		createLinkPkgReq: &rpc.CreatePackageAttestationRequest{
			Purl:   TestPurl,
			Bundle: data.SigstoreBundleLink(t),
		},
		createSLSAV1ProvenancePkgReq: &rpc.CreatePackageAttestationRequest{
			Purl:   TestPurl,
			Bundle: data.SigstoreBundleSLSA1Provenance(t),
		},
		createPkgAttReqWithOwnerRepoID: &rpc.CreatePackageAttestationRequest{
			Purl:         TestPurl,
			Bundle:       data.SigstoreBundle(t),
			OwnerId:      &ownerID,
			RepositoryId: &repoID,
		},
		createPkgAttReqSigstore100WithOwnerRepoID: &rpc.CreatePackageAttestationRequest{
			Purl:         TestPurl,
			Bundle:       data.SigstoreJs100ProtoBundle(t),
			OwnerId:      &ownerID,
			RepositoryId: &repoID,
		},
	}
}

// newExpectedProvenanceSummaryPb creates a new expected ProvenanceSummary protobuf object fixture
func newExpectedProvenanceSummaryPb() *rpc.ProvenanceSummary {
	expectedProvenanceSummary := rpc.ProvenanceSummary{
		SubjectAlternativeName:            "https://github.com/sigstore/sigstore-js/.github/workflows/publish.yml@refs/tags/v1.0.0",
		Issuer:                            "https://token.actions.githubusercontent.com",
		IssuerDisplayName:                 "GitHub Actions",
		BuildTrigger:                      "release",
		BuildConfigUri:                    "https://github.com/sigstore/sigstore-js/.github/workflows/publish.yml@refs/tags/v1.0.0",
		SourceRepositoryUri:               "https://github.com/sigstore/sigstore-js",
		SourceRepositoryDigest:            "06528997c3c8ab9f864fad9a3658446aca7fd86d",
		SourceRepositoryRef:               "refs/tags/v1.0.0",
		RunInvocationUri:                  "https://github.com/sigstore/sigstore-js/actions/runs/4137028816/attempts/1",
		ExpiresAt:                         timestamppb.New(time.Date(2023, time.February, 9, 18, 6, 0, 0, time.UTC)),
		IncludedAt:                        timestamppb.New(time.Date(2023, time.February, 9, 17, 56, 0, 0, time.UTC)),
		ResolvedSourceRepositoryCommitUri: "https://github.com/sigstore/sigstore-js/tree/06528997c3c8ab9f864fad9a3658446aca7fd86d",
		TransparencyLogUri:                "https://search.sigstore.dev/?logIndex=12988397",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		BuildConfigDisplayName:            ".github/workflows/publish.yml",
		ResolvedBuildConfigUri:            "https://github.com/sigstore/sigstore-js/actions/runs/4137028816/workflow",
	}
	return &expectedProvenanceSummary
}

// newExpectedSLSAV1ProvenanceSummaryPb creates a new expected SLSA V1 ProvenanceSummary protobuf object fixture
func newExpectedSLSAV1ProvenanceSummaryPb() *rpc.ProvenanceSummary {
	expectedProvenanceSummary := rpc.ProvenanceSummary{
		SubjectAlternativeName:            "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		Issuer:                            "https://token.actions.githubusercontent.com",
		IssuerDisplayName:                 "GitHub Actions",
		BuildTrigger:                      "workflow_dispatch",
		BuildConfigUri:                    "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		SourceRepositoryUri:               "https://github.com/github/package-security-learning-labs",
		SourceRepositoryDigest:            "4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		SourceRepositoryRef:               "refs/heads/main",
		RunInvocationUri:                  "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/attempts/1",
		ExpiresAt:                         timestamppb.New(time.Date(2023, time.June, 27, 12, 44, 16, 0, time.UTC)),
		IncludedAt:                        timestamppb.New(time.Date(2023, time.June, 27, 12, 34, 17, 0, time.UTC)),
		ResolvedSourceRepositoryCommitUri: "https://github.com/github/package-security-learning-labs/tree/4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		TransparencyLogUri:                "https://search.sigstore.dev/?logIndex=25278380",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		BuildConfigDisplayName:            ".github/workflows/npm-publish-with-provenance.yml",
		ResolvedBuildConfigUri:            "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/workflow",
	}
	return &expectedProvenanceSummary
}

/*
  Package Info Read API - GetPackageAttestations
    POST /twirp/github.trust_metadata_api.PackageInfoReadAPI/GetPackageAttestations
*/

// PackageInfoReadAPI/GetPackageAttestations
// Twirp Status Test: We should get a 200 if the package is found
func TestTwirpStatusCodePackageInfoReadAPIGetPackageAttestations(t *testing.T) {
	endpoint := "/twirp/github.trust_metadata_api.PackageInfoReadAPI/GetPackageAttestations"
	server, db, azClient := newServerWithDB(t)
	client := server.Client()
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	// Create the attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)

	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)
	_, err := twClientWrite.CreatePackageAttestation(ctx, fixture.createPkgAttReq)
	assert.Nil(t, err, "should not error")

	// Using the InfoRead HMAC Secret, test the endpoint status response code using JSON request
	payload := map[string]string{"purl": TestPurl}
	jsonValue, err := json.Marshal(payload)
	assert.Nil(t, err, "failed admirably to marshal payload")
	req, _ := http.NewRequest("POST", server.URL+endpoint, bytes.NewBuffer(jsonValue))
	req.Header.Set("Content-Type", "application/json")
	hmac, err := bodyhmac.CreateHeader(jsonValue, []byte(testHMACConfig.PkgRead[0].Keys[0]))
	assert.Nil(t, err)

	req.Header.Set(headers.RequestBodyHMAC, hmac)
	req.Header.Set(auth.HMACClientHeader, testHMACConfig.PkgRead[0].ClientID)
	resp, err := client.Do(req)

	assert.Nil(t, err)
	assert.Equal(t, 200, resp.StatusCode)
}

// PackageInfoReadAPI/GetPackageAttestations
// Twirp Status Test: We should get a 404 if the package is not found
func TestTwirpStatusCodePackageInfoReadAPIGetPackageAttestationsNotFound(t *testing.T) {
	endpoint := "/twirp/github.trust_metadata_api.PackageInfoReadAPI/GetPackageAttestations"
	server, db, azClient := newServerWithDB(t)
	client := server.Client()
	defer cleanUp(t, server, db, azClient)

	// Using the InfoRead HMAC Secret, test the endpoint status response code using JSON request
	payload := map[string]string{"purl": TestPurl}
	jsonValue, err := json.Marshal(payload)
	assert.Nil(t, err, "failed admirably to marshal payload")
	req, _ := http.NewRequest("POST", server.URL+endpoint, bytes.NewBuffer(jsonValue))
	req.Header.Set("Content-Type", "application/json")
	hmac, err := bodyhmac.CreateHeader(jsonValue, []byte(testHMACConfig.PkgRead[0].Keys[0]))
	assert.Nil(t, err)

	req.Header.Set(headers.RequestBodyHMAC, hmac)
	req.Header.Set(auth.HMACClientHeader, testHMACConfig.PkgRead[0].ClientID)
	resp, err := client.Do(req)

	assert.Nil(t, err)
	assert.Equal(t, 404, resp.StatusCode, "should return a 404 status code when no attestations are found")
}

// PackageInfoReadAPI/GetPackageAttestations
// get package attestation by purl
func TestPackageInfoReadAPIGetPackageAttestationByPurl(t *testing.T) {
	testFixture := newNPMFixture(t)
	testName := "GetPackageAttestion with Purl"
	server, db, azClient := newServerWithDB(t)

	// Create the attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(npmWriteAuthConfig.Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)
	ctx := createCtxWithHMACClientIDHeader(t, npmWriteAuthConfig.ClientID)
	_, err := twClientWrite.CreatePackageAttestation(ctx, testFixture.createPkgAttReq)
	assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", testName))

	// Get the attestation
	clientRead, _ := twcauth.NewBodyHMACSigner(npmReadAuthConfig.Keys[0], http.DefaultClient)
	twClientRead := rpc.NewPackageInfoReadAPIJSONClient(server.URL, clientRead)
	ctx = createCtxWithHMACClientIDHeader(t, npmReadAuthConfig.ClientID)
	resp, err := twClientRead.GetPackageAttestations(ctx, testFixture.getReq)

	assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", testName))
	assert.Len(t, resp.Attestations, 1, fmt.Sprintf("test '%s': should have one record", testName))

	cleanUp(t, server, db, azClient)
}

// PackageInfoReadAPI/GetPackageAttestations
// when fetching a package's attestations, if none exist it successfully returns an no matching attestations error
func TestPackageInfoReadAPINoneShouldBeEmptyResponse(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)

	// test the GetPackageAttestations endpoint
	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	req := &rpc.GetPackageAttestationsRequest{Purl: TestPurl}
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)
	_, err := twClient.GetPackageAttestations(ctx, req)

	assert.Equal(t, err, ErrNoMatchingAttestations, "should return an ErrNoMatchingAttestations error")
}

// PackageInfoReadAPI/GetPackageAttestations
// when fetching a package's attestations, if we provide a malformed purl we get an error
func TestPackageInfoReadAPIMalformedPurl(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	req := &rpc.GetPackageAttestationsRequest{Purl: BadPurl}
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)
	resp, err := twClient.GetPackageAttestations(ctx, req)

	assert.NotNil(t, err)
	assert.Nil(t, resp)
}

// PackageInfoReadAPI/GetPackageAttestations
// when fetching a package's attestations, if any exist we successfully return them
func TestPackageInfoReadAPIShouldReturnBundles(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	// Create the attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)
	_, err := twClientWrite.CreatePackageAttestation(ctx, fixture.createPkgAttReq)
	assert.Nil(t, err, "should not error")

	// Get the attestation
	req := &rpc.GetPackageAttestationsRequest{Purl: TestPurl}
	clientRead, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClientRead := rpc.NewPackageInfoReadAPIJSONClient(server.URL, clientRead)
	ctx = createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)
	resp, err := twClientRead.GetPackageAttestations(ctx, req)

	assert.Nil(t, err, "should not error")
	assert.Len(t, resp.Attestations, 1, "should have one record")
	assert.Equal(t, resp.Attestations[0].PredicateType, "https://slsa.dev/provenance/v0.2", "should have the correct attestation")
}

/*
  Package Info Read API - GetPackageProvenanceSummary
    POST /twirp/github.trust_metadata_api.PackageInfoReadAPI/GetPackageProvenanceSummary
*/

// getPackageProvenanceSummaryTestCase is a struct used for testing GetPackageProvenanceSummary
type getPackageProvenanceSummaryTestCase struct {
	name            string
	createPkgAttReq *rpc.CreatePackageAttestationRequest
	getPkgReq       *rpc.GetPackageProvenanceSummaryRequest
	readAuthConfig  auth.ClientConfig
	writeAuthConfig auth.ClientConfig
	result          *rpc.GetPackageProvenanceSummaryResponse
}

// PackageInfoReadAPI/GetPackageProvenanceSummary
func TestPackageProvenanceReadAPIGetPackageProvenanceSummaryByPurl(t *testing.T) {
	testFixture := newNPMFixture(t)
	testcases := []getPackageProvenanceSummaryTestCase{
		{
			name:            "GetPackageProvenanceSummary with valid purl, and no provenance attestations",
			createPkgAttReq: testFixture.createLinkPkgReq,
			getPkgReq:       testFixture.getPkgProvenanceReq,
			readAuthConfig:  npmReadAuthConfig,
			writeAuthConfig: npmWriteAuthConfig,
			result:          nil,
		},
		{
			name:            "GetPackageProvenanceSummary with valid purl and valid provenance attestation",
			createPkgAttReq: testFixture.createPkgAttReqSigstore100,
			getPkgReq:       testFixture.getPkgProvenanceReq,
			readAuthConfig:  npmReadAuthConfig,
			writeAuthConfig: npmWriteAuthConfig,
			result:          testFixture.getPkgProvenanceResp,
		},
		{
			name:            "GetPackageProvenanceSummary with valid purl and valid SLSA V1 provenance attestation",
			createPkgAttReq: testFixture.createSLSAV1ProvenancePkgReq,
			getPkgReq:       testFixture.getPkgProvenanceReq,
			readAuthConfig:  npmReadAuthConfig,
			writeAuthConfig: npmWriteAuthConfig,
			result:          testFixture.getPkgSLSAV1ProvenanceResp,
		},
	}

	for _, tc := range testcases {
		server, db, azClient := newServerWithDB(t)

		// Create the attestation
		clientWrite, _ := twcauth.NewBodyHMACSigner(tc.writeAuthConfig.Keys[0], http.DefaultClient)
		twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)
		ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.writeAuthConfig.ClientID))

		_, err := twClientWrite.CreatePackageAttestation(ctx, tc.createPkgAttReq)
		assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))

		// Get the attestation
		clientRead, _ := twcauth.NewBodyHMACSigner(tc.readAuthConfig.Keys[0], http.DefaultClient)
		twClientRead := rpc.NewPackageInfoReadAPIJSONClient(server.URL, clientRead)
		ctx = createCtxWithHMACClientIDHeader(t, tc.readAuthConfig.ClientID)
		resp, err := twClientRead.GetPackageProvenanceSummary(ctx, tc.getPkgReq)

		if tc.result != nil {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
			assert.NotNil(t, resp, fmt.Sprintf("test '%s': response should not be nil", tc.name))

			provenanceSummary := resp.ProvenanceSummary
			assert.NotNil(t, provenanceSummary, fmt.Sprintf("test '%s': ProvenanceSummary should not be nil", tc.name))
			expectedProvenanceSummary := tc.result.ProvenanceSummary

			tmatesting.CompareProvenanceSummary(t, expectedProvenanceSummary, provenanceSummary)
		} else {
			assert.NotNil(t, err, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, resp, fmt.Sprintf("test '%s': response should be nil", tc.name))
		}

		cleanUp(t, server, db, azClient)
	}
}

// PackageInfoReadAPI/GetPackageProvenanceSummary
// Test what happens if, in addition to a provenance attestation, there are non-provenance attestations
func TestPackageInfoReadAPIGetPackageProvenanceSummaryMultipleAttestations(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	// Create the provenance attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)

	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID))

	_, err := twClientWrite.CreatePackageAttestation(ctx, fixture.createPkgAttReqSigstore100)
	assert.Nil(t, err, "should not error")

	// Create the link attestation
	_, err = twClientWrite.CreatePackageAttestation(ctx, fixture.createLinkPkgReq)
	assert.Nil(t, err, "should not error")

	// Get the provenance
	req := &rpc.GetPackageProvenanceSummaryRequest{Purl: TestPurl}
	clientRead, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClientRead := rpc.NewPackageInfoReadAPIJSONClient(server.URL, clientRead)
	ctx = createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)
	resp, err := twClientRead.GetPackageProvenanceSummary(ctx, req)

	assert.Nil(t, err, "should not error")
	assert.NotNil(t, resp, "response should not be nil")

	provenanceSummary := resp.ProvenanceSummary
	assert.NotNil(t, provenanceSummary, "ProvenanceSummary should not be nil")

	expectedProvenanceSummary := fixture.getPkgProvenanceResp.ProvenanceSummary

	tmatesting.CompareProvenanceSummary(t, expectedProvenanceSummary, provenanceSummary)
}

// PackageInfoReadAPI/GetPackageProvenanceSummary
// when fetching a package's provenance, if none exist it successfully returns an empty response
func TestPackageProvenanceReadAPINoneShouldBeEmptyResponse(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	req := &rpc.GetPackageProvenanceSummaryRequest{Purl: TestPurl}
	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID))

	_, err := twClient.GetPackageProvenanceSummary(ctx, req)

	assert.Equal(t, err.Error(), "twirp error not_found: no attestation for given (purl, predicateType) exists")
}

// PackageInfoReadAPI/GetPackageProvenanceSummary
// when fetching a package's provenance, if we provide a malformed purl we get an error
func TestPackageProvenanceReadAPIMalformedPurl(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	req := &rpc.GetPackageProvenanceSummaryRequest{Purl: BadPurl}
	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID))

	resp, err := twClient.GetPackageProvenanceSummary(ctx, req)

	assert.NotNil(t, err)
	assert.Nil(t, resp)
	assert.Equal(t, err.Error(), "twirp error invalid_argument: purl is not valid: purl scheme is not \"pkg\": \"\"")
}

/*
  Package Info Write API
	  POST /twirp/github.trust_metadata_api.PackageInfoWriteAPI/CreatePackageAttestation
*/

// PackageInfoWriteAPI/CreatePackageAttestation
// after publishing an attestation, ensure it exists in the database
func TestPackageInfoWriteAPIPublishingAttestation(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	// Create the attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)
	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID))

	_, err := twClientWrite.CreatePackageAttestation(ctx, fixture.createPkgAttReq)
	assert.Nil(t, err, "should not error")

	// Get the attestation
	req := &rpc.GetPackageAttestationsRequest{Purl: TestPurl}
	clientRead, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClientRead := rpc.NewPackageInfoReadAPIJSONClient(server.URL, clientRead)
	ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID))

	resp, err := twClientRead.GetPackageAttestations(ctx, req)

	assert.Nil(t, err, "should not error")
	assert.Len(t, resp.Attestations, 1, "should have one record")
}

// PackageInfoWriteAPI/CreatePackageAttestation
// publish attestation with owner ID and repo ID
func TestPackageInfoWriteAPIPublishingAttestationWithOwnerIDAndRepoID(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	// Create the attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)

	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)
	// ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	_, err := twClientWrite.CreatePackageAttestation(ctx, fixture.createPkgAttReqWithOwnerRepoID)
	assert.Nil(t, err, "should not error")

	// Get the attestation
	req := &rpc.GetPackageAttestationsRequest{Purl: TestPurl}
	clientRead, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClientRead := rpc.NewPackageInfoReadAPIJSONClient(server.URL, clientRead)
	ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID))

	resp, err := twClientRead.GetPackageAttestations(ctx, req)

	assert.Nil(t, err, "should not error")
	assert.Len(t, resp.Attestations, 1, "should have one record")
}

// PackageInfoWriteAPI/CreatePackageAttestation
// trying to publish an attestation with a X-HMAC-Client-Id value that doesn't match the client ID
// in the provided HMAC auth config should return an error
func TestPackageInfoWriteMismatchedClientID(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	// Create the attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)

	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, "some-other-client-id"))

	_, err := twClientWrite.CreatePackageAttestation(ctx, fixture.createPkgAttReq)
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code())
}

// PackageInfoWriteAPI/CreatePackageAttestation
// trying to publish an attestation with an unsupported client ID should return an error
func TestPackageInfoWriteUnsupportedClientID(t *testing.T) {
	svrConfig := ServerAuthConfig{
		LegacyTMA: []auth.ClientConfig{
			{
				ClientID: "some-other-client-id",
				Domain:   "some-other-domain",
				Keys:     []string{"some-other-key"},
			},
		},
		PkgRead: []auth.ClientConfig{
			{
				ClientID: "some-other-client-id",
				Domain:   "some-other-domain",
				Keys:     []string{"some-other-key"},
			},
		},
		PkgWrite: []auth.ClientConfig{
			{
				ClientID: "some-other-client-id",
				Domain:   "some-other-domain",
				Keys:     []string{"some-other-key"},
			},
		},
		Dotcom: []auth.ClientConfig{
			{
				ClientID: "some-other-client-id",
				Domain:   "some-other-domain",
				Keys:     []string{"some-other-key"},
			},
		},
	}

	server, db, azClient := newServerWithDB(t, WithHMACConfig(svrConfig))
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	// Create the attestation
	clientWrite, _ := twcauth.NewBodyHMACSigner(svrConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)

	ctx := createCtxWithHMACClientIDHeader(t, svrConfig.PkgWrite[0].ClientID)
	_, err := twClientWrite.CreatePackageAttestation(ctx, fixture.createPkgAttReq)
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code())
}

// PackageInfoWriteAPI/CreatePackageAttestation
// trying to publish an attestation with a client ID that doesn't match a domain should return an error
func TestPackageInfoWriteClientIDNoMatchingDomainID(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	// Create the attestation
	clientWrite := http.DefaultClient
	twClientWrite := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, clientWrite)

	ctx := createCtxWithHMACClientIDHeader(t, "some-other-client-id")
	_, err := twClientWrite.CreatePackageAttestation(ctx, fixture.createPkgAttReq)
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code())
}

// PackageInfoWriteAPI/CreatePackageAttestation
// Twirp Status Test: We should get a 200 when successfully creating an attestation
func TestTwirpStatusCodePackageInfoWriteAPICreatePackageAttestation(t *testing.T) {
	endpoint := "/twirp/github.trust_metadata_api.PackageInfoWriteAPI/CreatePackageAttestation"
	server, db, azClient := newServerWithDB(t)
	client := server.Client()
	defer cleanUp(t, server, db, azClient)
	fixture := newNPMFixture(t)

	req, _ := http.NewRequest("POST", server.URL+endpoint, bytes.NewBuffer(fixture.twirpRequestRaw))
	req.Header.Set("Content-Type", "application/json")
	hmac, err := bodyhmac.CreateHeader(fixture.twirpRequestRaw, []byte(testHMACConfig.PkgWrite[0].Keys[0]))
	assert.Nil(t, err)
	req.Header.Set(headers.RequestBodyHMAC, hmac)
	req.Header.Set(auth.HMACClientHeader, testHMACConfig.PkgWrite[0].ClientID)
	resp, err := client.Do(req)

	assert.Nil(t, err)
	assert.Equal(t, 200, resp.StatusCode)
}

/*
  TMA HMAC: ReadOnly
*/
// TMA HMAC: ReadOnly errors when the HMAC is missing
func TestHMACReadOnlyMissingShouldError(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	getReq := newNPMFixture(t).getReq

	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, http.DefaultClient)
	_, err := twClient.GetPackageAttestations(context.Background(), getReq)

	assert.NotNil(t, err)
	var twirpErr twirp.Error
	if assert.ErrorAs(t, err, &twirpErr) {
		assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), "should error with twirp.Unauthenticated when the HMAC ReadOnly is missing")
	}
}

// TMA HMAC: ReadOnly errors when the body HMAC is present but invalid
func TestBodyHMACReadOnlyPresentButInvalidShouldError(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	getReq := newNPMFixture(t).getReq

	client, _ := twcauth.NewBodyHMACSigner("invalid hmac", http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)
	_, err := twClient.GetPackageAttestations(ctx, getReq)

	assert.NotNil(t, err, "should error with twirp.Unauthenticated when the HMAC ReadOnly is present but invalid")
	var twirpErr twirp.Error
	if assert.ErrorAs(t, err, &twirpErr) {
		assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), "should error with twirp.Unauthenticated when the HMAC is present but invalid")
	}
}

// TMA HMAC: ReadOnly works when the body HMAC is present and valid
func TestBodyHMACReadOnlyPresentAndValid(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	getReq := newNPMFixture(t).getReq

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)
	_, err := twClient.GetPackageAttestations(ctx, getReq)

	assert.NotNil(t, err, "should error when no attestations are found")
	assert.ErrorAs(t, err, &ErrNoMatchingAttestations, "should error with ErrNoMatchingAttestations when no attestations are found")
}

// TMA HMAC: Can't use the body HMAC TMA API key for the ReadOnly service
func TestBodyHMACReadOnlyPresentAndValidCantUseTMAKey(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	getReq := newNPMFixture(t).getReq

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)
	_, err := twClient.GetPackageAttestations(ctx, getReq)
	assert.NotNil(t, err)

	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), "should error with Unauthenticated when the TMA HMAC is present but ReadOnly is called")
}

/*
  TMA HMAC: Write
*/
// TMA HMAC: Write errors when the HMAC is missing
func TestHMACWriteMissingShouldError(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	createPkgAttReq := newNPMFixture(t).createPkgAttReq

	twClient := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, http.DefaultClient)
	_, err := twClient.CreatePackageAttestation(context.Background(), createPkgAttReq)

	assert.NotNil(t, err, "should error when the HMAC is missing")
	var twirpErr twirp.Error
	if assert.ErrorAs(t, err, &twirpErr) {
		assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), "should error with Unauthenticated")
	}
}

// TMA HMAC: Write errors when the body HMAC is present but invalid
func TestBodyHMACWritePresentButInvalidShouldError(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	createPkgAttReq := newNPMFixture(t).createPkgAttReq

	client, _ := twcauth.NewBodyHMACSigner("invalid hmac", http.DefaultClient)
	twClient := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, client)
	_, err := twClient.CreatePackageAttestation(context.Background(), createPkgAttReq)

	assert.NotNil(t, err, "should error when the HMAC is present but invalid")
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), "should error with Unauthenticated")
}

// TMA HMAC: Write works when the body HMAC is present and valid
func TestBodyHMACWritePresentAndValid(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	createPkgAttReq := newNPMFixture(t).createPkgAttReq

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgWrite[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, client)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)
	_, err := twClient.CreatePackageAttestation(ctx, createPkgAttReq)

	assert.Nil(t, err, "should succeed when the HMAC is present and valid")
}

// TMA HMAC: Can't use the PackageReadAPI key for the PackageWriteAPI service body HMAC
func TestBodyHMACWritePresentAndValidCantUseTMAKey(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	createPkgAttReq := newNPMFixture(t).createPkgAttReq

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoWriteAPIJSONClient(server.URL, client)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)
	_, err := twClient.CreatePackageAttestation(ctx, createPkgAttReq)

	assert.NotNil(t, err, "should return an error")
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), "should return an Unauthenticated error")
}
