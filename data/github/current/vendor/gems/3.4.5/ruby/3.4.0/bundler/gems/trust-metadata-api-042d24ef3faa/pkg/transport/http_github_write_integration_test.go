//go:build integration

package transport

import (
	"net/http"
	"testing"

	twcauth "github.com/github/go-twirp/v2/client/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/testing/data"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
)

// fixture represents the protobuf rpc data used for testing
type fixtureGitHubAPI struct {
	tenantIDForHeader string
	// GitHubAPI/CreateAttestationByOwnerRepository
	createArtifactAttReq            *rpc.CreateAttestationByOwnerRepositoryRequest
	createArtifactMissingOwnerIDReq *rpc.CreateAttestationByOwnerRepositoryRequest
	createArtifactMissingRepoIDReq  *rpc.CreateAttestationByOwnerRepositoryRequest
	createArtifactMissingBundleReq  *rpc.CreateAttestationByOwnerRepositoryRequest
	// GitHubAPI/ListAttestationsBySubjectDigest
	getPkgBySubjectDigestReqWithOwnerRepoID *rpc.ListAttestationsBySubjectDigestRequest
	// GitHubAPI/ListAttestationsByRepository
	listAttByRepoReq *rpc.ListAttestationsByRepositoryRequest
	// GitHubAPI/CreateReleaseAttestation
	createReleaseAttReq *rpc.CreateReleaseAttestationRequest
}

// newFixtureGitHubAPI constructs a new fixtureGitHubAPI
func newFixtureGitHubAPI(t *testing.T) *fixtureGitHubAPI {
	ownerID, repoID := uint64(42), uint64(12345)
	tenantID := "123123"

	return &fixtureGitHubAPI{
		tenantIDForHeader: tenantID,
		// GitHubAPI/ListAttestationsByRepository
		listAttByRepoReq: &rpc.ListAttestationsByRepositoryRequest{
			OwnerId:      ownerID,
			RepositoryId: repoID,
		},
		// GitHubAPI/ListAttestationsBySubjectDigest
		getPkgBySubjectDigestReqWithOwnerRepoID: &rpc.ListAttestationsBySubjectDigestRequest{
			SubjectDigest: SubjectDigestOfSigstoreBundleFromGenerateBuildProvenance,
			OwnerId:       ownerID,
			RepositoryId:  &repoID,
		},
		// GitHubAPI/CreateAttestationByOwnerRepository
		createArtifactAttReq: &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       data.SigstoreBundleFromGenerateBuildProvenance(t),
			OwnerId:      ownerID,
			RepositoryId: repoID,
		},
		createArtifactMissingOwnerIDReq: &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       data.SigstoreBundleFromGenerateBuildProvenance(t),
			OwnerId:      0,
			RepositoryId: repoID,
		},
		createArtifactMissingRepoIDReq: &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       data.SigstoreBundleFromGenerateBuildProvenance(t),
			OwnerId:      ownerID,
			RepositoryId: 0,
		},
		createArtifactMissingBundleReq: &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       nil,
			OwnerId:      ownerID,
			RepositoryId: repoID,
		},
		// GitHubAPI/CreateReleaseAttestation
		createReleaseAttReq: &rpc.CreateReleaseAttestationRequest{
			Bundle:       data.SigstoreBundleGitHubRelease(t),
			OwnerId:      ownerID,
			RepositoryId: repoID,
		},
	}
}

/*
  GitHubAPI - CreateAttestationByOwnerRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/CreateAttestationByOwnerRepository
*/

// GitHubAPI: CreateAttestationByOwnerRepository
// trying to create an attestation with the wrong HMAC client ID should fail
func TestCreateAttestationByOwnerRepository_BadHMACClientID(t *testing.T) {
	testcases := []struct{ name, hmacClientID string }{
		{
			name:         "CreateAttestationByOwnerRepository with unknown HMAC client ID",
			hmacClientID: "unknown-client-id",
		},
		{
			name:         "CreateAttestationByOwnerRepository with npm write HMAC client ID",
			hmacClientID: testHMACConfig.PkgWrite[0].ClientID,
		},
	}

	for _, tc := range testcases {
		server, _, cleanUp := newServerWithDB(t)
		fixture := newFixtureGitHubAPI(t)

		// Create the attestation
		clientDotcom, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotcom)

		ctx := createCtxWithHMACClientIDHeader(t, tc.hmacClientID)
		_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)
		var twirpErr twirp.Error
		assert.ErrorAs(t, err, &twirpErr, tc.name)
		assert.Equal(t, twirp.Unauthenticated, twirpErr.Code(), tc.name)

		cleanUp(t)
	}
}

// GitHubAPI: CreateAttestationByOwnerRepository
func TestGitHubAPIPublishingAttestationWithCorrectSlsaV1Provenance(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID)

	createReq := fixture.createArtifactAttReq
	createReq.Bundle = data.SigstoreBundleFromGenerateBuildProvenance(t)
	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, createReq)
	assert.NoError(t, err)

	// Get the attestation by repo
	listAttByRepoReq := fixture.listAttByRepoReq
	repoResp, err := twClientDotcom.ListAttestationSummariesByRepository(ctx, listAttByRepoReq)

	assert.NoError(t, err)
	assert.Len(t, repoResp.AttestationSummaries, 1, "should have one record")
	assert.Equal(t, uint64(42), repoResp.AttestationSummaries[0].OwnerId, "should have the same owner ID")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// trying to publish attestation with invalid SLSA V1 provenance should fail
func TestGitHubAPIPublishingAttestationWithInvalidSlsaV1Provenance(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID)

	createReq := fixture.createArtifactAttReq
	createReq.Bundle = data.SigstoreBundleFromGenerateBuildProvenanceInvalidOIDs(t)
	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, createReq)
	assert.Error(t, err)
	assert.Equal(t, "twirp error invalid_argument: values do not match: https://github.com/wrong/github-early-access/generate-build-provenance != https://github.com/github-early-access/generate-build-provenance", err.Error())

	// Get the attestation by repo
	listAttByRepoReq := fixture.listAttByRepoReq
	_, err = twClientDotcom.ListAttestationSummariesByRepository(ctx, listAttByRepoReq)

	assert.Error(t, err)
	assert.Equal(t, err.Error(), "twirp error not_found: no matching attestations found")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// after publishing an attestation, should be able to retrieve it by subject digest & repository
func TestGitHubAPIPublishingAttestation(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID)

	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)
	assert.NoError(t, err)

	// Get the attestation by subject digest
	req := fixture.getPkgBySubjectDigestReqWithOwnerRepoID
	resp, err := twClientDotcom.ListAttestationsBySubjectDigest(ctx, req)

	assert.NoError(t, err)
	assert.Len(t, resp.Attestations, 1, "should have one record")
	assert.Equal(t, uint64(0), resp.Attestations[0].TenantId, "should have the same tenant ID")

	// Get the attestation by repo
	listAttByRepoReq := fixture.listAttByRepoReq
	repoResp, err := twClientDotcom.ListAttestationSummariesByRepository(ctx, listAttByRepoReq)

	assert.NoError(t, err)
	assert.Len(t, repoResp.AttestationSummaries, 1, "should have one record")
	assert.Equal(t, uint64(42), repoResp.AttestationSummaries[0].OwnerId, "should have the same owner ID")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// after publishing an attestation, should have tenant ID
func TestGitHubAPIPublishingAttestationWithTenantID(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)
	ctx := createCtxWithTenantIDAndHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID, fixture.tenantIDForHeader)

	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)
	assert.NoError(t, err)

	// Get the attestation by subject digest
	req := fixture.getPkgBySubjectDigestReqWithOwnerRepoID
	resp, err := twClientDotcom.ListAttestationsBySubjectDigest(ctx, req)

	assert.NoError(t, err)
	assert.Len(t, resp.Attestations, 1, "should have one record")
	assert.Equal(t, uint64(123123), resp.Attestations[0].TenantId, "should have the same tenant ID")

	// Get the attestation by repo
	listAttByRepoReq := fixture.listAttByRepoReq
	repoResp, err := twClientDotcom.ListAttestationSummariesByRepository(ctx, listAttByRepoReq)

	assert.NoError(t, err)
	assert.Len(t, repoResp.AttestationSummaries, 1, "should have one record")
	assert.Equal(t, uint64(42), repoResp.AttestationSummaries[0].OwnerId, "should have the same owner ID")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// only allows to publish with valid tenant ID
func TestGitHubAPIPublishingAttestationWithInvalidTenantID(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)
	ctx := createCtxWithTenantIDAndHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID, "+1231312")

	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)

	assert.Error(t, err, "error for tenant id should be returned")
}

func TestGitHubAPICreateAttestationByOwnerRepository_TwirpInvalidArgument(t *testing.T) {
	testFixture := newFixtureGitHubAPI(t)
	testcases := []struct {
		name                 string
		createArtifactAttReq *rpc.CreateAttestationByOwnerRepositoryRequest
	}{
		{
			name:                 "CreateAttestationByOwnerRepository with missing owner ID",
			createArtifactAttReq: testFixture.createArtifactMissingOwnerIDReq,
		},
		{
			name:                 "CreateAttestationByOwnerRepository with missing repo ID",
			createArtifactAttReq: testFixture.createArtifactMissingRepoIDReq,
		},
		{
			name:                 "CreateAttestationByOwnerRepository with missing bundle",
			createArtifactAttReq: testFixture.createArtifactMissingBundleReq,
		},
	}

	for _, tc := range testcases {
		server, _, cleanUp := newServerWithDB(t)

		// Create the attestation
		clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

		ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID)

		_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, tc.createArtifactAttReq)
		var twirpErr twirp.Error
		assert.ErrorAs(t, err, &twirpErr, tc.name)
		assert.Equal(t, twirp.InvalidArgument, twirpErr.Code(), tc.name)

		cleanUp(t)
	}
}

// GitHubAPI: CreateReleaseAttestation
func TestCreateReleaseAttestation(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)
	fixture := newFixtureGitHubAPI(t)

	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID)

	_, err := twClientDotcom.CreateReleaseAttestation(ctx, fixture.createReleaseAttReq)
	assert.NoError(t, err)

	// Creating a second attestation with the same release tag should fail
	// TODO: Add test data with different attestations but same release tags
	_, err = twClientDotcom.CreateReleaseAttestation(ctx, fixture.createReleaseAttReq)
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.AlreadyExists, twirpErr.Code())
}
