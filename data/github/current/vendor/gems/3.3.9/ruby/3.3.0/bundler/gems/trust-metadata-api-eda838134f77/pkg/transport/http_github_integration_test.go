//go:build integration

package transport

import (
	"fmt"
	"net/http"
	"testing"

	twcauth "github.com/github/go-twirp/v2/client/auth"
	"github.com/github/trust-metadata-api/pkg/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
	v1 "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
)

// fixture represents the protobuf rpc data used for testing
type fixtureGitHubAPI struct {
	tenantIDForHeader string
	bundle            *v1.Bundle
	twirpRequestRaw   []byte
	// GitHubAPI/CreateAttestationByOwnerRepository
	createPkgAttReqSigstore300WithOwnerRepoID *rpc.CreateAttestationByOwnerRepositoryRequest
	createArtifactAttReq                      *rpc.CreateAttestationByOwnerRepositoryRequest
	// GitHubAPI/GetAttestationByRepository
	getAttByIdReq        *rpc.GetAttestationByRepositoryRequest
	getAttByInvalidIdReq *rpc.GetAttestationByRepositoryRequest
	// GitHubAPI/ListAttestationsBySubjectDigest
	getPkgBySubjectDigestReq                *rpc.ListAttestationsBySubjectDigestRequest
	getPkgBySubjectDigestReqWithOwnerRepoID *rpc.ListAttestationsBySubjectDigestRequest
	// GitHubAPI/ListAttestationsByRepository
	listAttByRepoReq *rpc.ListAttestationsByRepositoryRequest
	// GitHubAPI/GetAttestationSummaryByRepository
	showAttByIdReq        *rpc.GetAttestationSummaryByRepositoryRequest
	showAttByInvalidIdReq *rpc.GetAttestationSummaryByRepositoryRequest
	// GitHubnAPI/ListAttestationSummariesByRepository
	listAttSumByIdReq          *rpc.ListAttestationsByRepositoryRequest
	listAttSumByIdInvalidIdReq *rpc.ListAttestationsByRepositoryRequest
}

// newFixtureGitHubAPI constructs a new fixtureGitHubAPI
func newFixtureGitHubAPI(t *testing.T) *fixtureGitHubAPI {
	ownerID, repoID := uint64(42), uint64(12345)
	tenantID := "123123"

	return &fixtureGitHubAPI{
		tenantIDForHeader: tenantID,
		bundle:            data.SigstoreBundleFromGenerateBuildProvenance(t),
		twirpRequestRaw:   data.TwirpRequestRaw,
		// GitHubAPI/ListAttestationsByRepository
		listAttByRepoReq: &rpc.ListAttestationsByRepositoryRequest{
			OwnerId:      ownerID,
			RepositoryId: repoID,
		},
		// GitHubAPI/ListAttestationsBySubjectDigest
		getPkgBySubjectDigestReq: &rpc.ListAttestationsBySubjectDigestRequest{
			SubjectDigest: SubjectDigest,
		},
		getPkgBySubjectDigestReqWithOwnerRepoID: &rpc.ListAttestationsBySubjectDigestRequest{
			SubjectDigest: SubjectDigestOfSigstoreBundleFromGenerateBuildProvenance,
			OwnerId:       ownerID,
			RepositoryId:  &repoID,
		},
		// GitHubAPI/CreateAttestationByOwnerRepository
		createPkgAttReqSigstore300WithOwnerRepoID: &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       data.SigstoreJs300ProtoBundle(t),
			OwnerId:      ownerID,
			RepositoryId: repoID,
		},
		createArtifactAttReq: &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       data.SigstoreBundleFromGenerateBuildProvenance(t),
			OwnerId:      ownerID,
			RepositoryId: repoID,
		},
		// GitHubAPI/GetAttestationByRepository
		getAttByIdReq: &rpc.GetAttestationByRepositoryRequest{
			AttestationId: 0, // 0 is special and means we want the last created attestation
			OwnerId:       &ownerID,
			RepositoryId:  &repoID,
		},
		getAttByInvalidIdReq: &rpc.GetAttestationByRepositoryRequest{
			AttestationId: 8221,
			OwnerId:       &ownerID,
			RepositoryId:  &repoID,
		},
		// GitHubAPI/GetAttestationSummaryByRepository
		showAttByIdReq: &rpc.GetAttestationSummaryByRepositoryRequest{
			AttestationId: 0,
			OwnerId:       &ownerID,
			RepositoryId:  &repoID,
		},
		showAttByInvalidIdReq: &rpc.GetAttestationSummaryByRepositoryRequest{
			AttestationId: 8221,
			OwnerId:       &ownerID,
			RepositoryId:  &repoID,
		},
	}
}

/*
  GitHubAPI - CreateAttestationByOwnerRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/CreateAttestationByOwnerRepository
*/

// GitHubAPI: CreateAttestationByOwnerRepository
// trying to create an attestation with an unknown client ID should fail
func TestGitHubAPIClientIDNoMatchingDomainID(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, "some-other-client-id"))

	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code())
}

// GitHubAPI: CreateAttestationByOwnerRepository
func TestGitHubAPIPublishingAttestationWithCorrectSlsaV1Provenance(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID))

	createReq := fixture.createArtifactAttReq
	createReq.Bundle = data.SigstoreBundleFromGenerateBuildProvenance(t)
	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, createReq)
	assert.Nil(t, err, "should not error")

	// Get the attestation by repo
	listAttByRepoReq := fixture.listAttByRepoReq
	repoResp, err := twClientDotcom.ListAttestationsByRepositorySummary(ctx, listAttByRepoReq)

	assert.Nil(t, err, "should not error")
	assert.Len(t, repoResp.AttestationSummaries, 1, "should have one record")
	assert.Equal(t, uint64(42), repoResp.AttestationSummaries[0].OwnerId, "should have the same owner ID")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// trying to publish attestation with invalid SLSA V1 provenance should fail
func TestGitHubAPIPublishingAttestationWithInvalidSlsaV1Provenance(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID))

	createReq := fixture.createArtifactAttReq
	createReq.Bundle = data.SigstoreBundleFromGenerateBuildProvenanceInvalidOIDs(t)
	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, createReq)
	assert.NotNil(t, err, "should error")
	assert.Equal(t, err.Error(), "twirp error invalid_argument: values do not match: https://github.com/wrong/github-early-access/generate-build-provenance != https://github.com/github-early-access/generate-build-provenance")

	// Get the attestation by repo
	listAttByRepoReq := fixture.listAttByRepoReq
	_, err = twClientDotcom.ListAttestationsByRepositorySummary(ctx, listAttByRepoReq)

	assert.NotNil(t, err, "should error")
	assert.Equal(t, err.Error(), "twirp error not_found: no matching attestations found")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// after publishing an attestation, should be able to retrieve it by subject digest & repository
func TestGitHubAPIPublishingAttestation(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)
	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID))

	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)
	assert.Nil(t, err, "should not error")

	// Get the attestation by subject digest
	req := fixture.getPkgBySubjectDigestReqWithOwnerRepoID
	resp, err := twClientDotcom.ListAttestationsBySubjectDigest(ctx, req)

	assert.Nil(t, err, "should not error")
	assert.Len(t, resp.Attestations, 1, "should have one record")
	assert.Equal(t, uint64(0), resp.Attestations[0].TenantId, "should have the same tenant ID")

	// Get the attestation by repo
	listAttByRepoReq := fixture.listAttByRepoReq
	repoResp, err := twClientDotcom.ListAttestationsByRepositorySummary(ctx, listAttByRepoReq)

	assert.Nil(t, err, "should not error")
	assert.Len(t, repoResp.AttestationSummaries, 1, "should have one record")
	assert.Equal(t, uint64(42), repoResp.AttestationSummaries[0].OwnerId, "should have the same owner ID")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// after publishing an attestation, should have tenent ID
func TestGitHubAPIPublishingAttestationWithTenantID(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)
	ctx := createCtxWithTestClientIpAddr(createCtxWithTenantIDAndHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID, fixture.tenantIDForHeader))

	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)
	assert.Nil(t, err, "should not error")

	// Get the attestation by subject digest
	req := fixture.getPkgBySubjectDigestReqWithOwnerRepoID
	resp, err := twClientDotcom.ListAttestationsBySubjectDigest(ctx, req)

	assert.Nil(t, err, "should not error")
	assert.Len(t, resp.Attestations, 1, "should have one record")
	assert.Equal(t, uint64(123123), resp.Attestations[0].TenantId, "should have the same tenant ID")

	// Get the attestation by repo
	listAttByRepoReq := fixture.listAttByRepoReq
	repoResp, err := twClientDotcom.ListAttestationsByRepositorySummary(ctx, listAttByRepoReq)

	assert.Nil(t, err, "should not error")
	assert.Len(t, repoResp.AttestationSummaries, 1, "should have one record")
	assert.Equal(t, uint64(42), repoResp.AttestationSummaries[0].OwnerId, "should have the same owner ID")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// only allows publish with valid tenant ID
func TestGitHubAPIPublishingAttestationWithInvalidTenantID(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)
	ctx := createCtxWithTestClientIpAddr(createCtxWithTenantIDAndHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID, "+1231312"))

	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)

	assert.Error(t, err, "error for tenant id should be returned")
}

// GitHubAPI: CreateAttestationByOwnerRepository
// trying to publish an attestation with an unsupported client ID should return an error
func TestGitHubAPIMismatchedClientID(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, "some-other-client-id"))

	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code())
}

/*
  GitHubAPI - ListAttestationsBySubjectDigest
	  POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationsBySubjectDigest
*/

// GitHubAPI: ListAttestationsBySubjectDigest
// when fetching a package's attestations, if we provide a malformed subject digest we get an error
func TestGitHubAPIMalformedSubjectDigest(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)

	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	req := &rpc.ListAttestationsBySubjectDigestRequest{SubjectDigest: "12312"}
	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID))

	resp, err := twClient.ListAttestationsBySubjectDigest(ctx, req)

	assert.NotNil(t, err)
	assert.Nil(t, resp)
}

type listAttestationsBySubjectDigestTestCase struct {
	name                     string
	createArtifactAttReq     *rpc.CreateAttestationByOwnerRepositoryRequest
	getPkgBySubjectDigestReq *rpc.ListAttestationsBySubjectDigestRequest
	cursor                   *mysql.Cursor
	readAuthConfig           auth.ClientConfig
	writeAuthConfig          auth.ClientConfig
	expectedErr              string
	expectedIds              []uint64
	numOfAttestations        int
	pageInfo                 *rpc.PageInfo
}

// GitHubAPI: ListAttestationsBySubjectDigest
func TestGitHubAPIListAttestationsBySubjectDigest(t *testing.T) {
	testFixture := newFixtureGitHubAPI(t)
	testcases := []listAttestationsBySubjectDigestTestCase{
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID without cursor",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "",
			expectedIds:              []uint64{5, 4, 3, 2, 1},
			numOfAttestations:        5,
			pageInfo:                 &rpc.PageInfo{StartCursor: 5, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID without cursor but have more",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "",
			expectedIds:              []uint64{31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2},
			numOfAttestations:        31,
			pageInfo:                 &rpc.PageInfo{StartCursor: 31, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID with cursor per page 1",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			cursor:                   &mysql.Cursor{PerPage: 1},
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "",
			expectedIds:              []uint64{10},
			numOfAttestations:        10,
			pageInfo:                 &rpc.PageInfo{StartCursor: 10, EndCursor: 10, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID with cursor per page 2 with after and reach to end",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			cursor:                   &mysql.Cursor{PerPage: 2, After: uint64(3)},
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "",
			expectedIds:              []uint64{2, 1},
			numOfAttestations:        10,
			pageInfo:                 &rpc.PageInfo{StartCursor: 2, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID with cursor with after and not reach to end",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			cursor:                   &mysql.Cursor{PerPage: 2, After: uint64(4)},
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "",
			expectedIds:              []uint64{3, 2},
			numOfAttestations:        10,
			pageInfo:                 &rpc.PageInfo{StartCursor: 3, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID with cursor with after and no more data to read",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			cursor:                   &mysql.Cursor{PerPage: 2, After: uint64(1)},
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "twirp error not_found: no matching attestations found",
			expectedIds:              []uint64{},
			numOfAttestations:        10,
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID with cursor with before and not reach to end",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			cursor:                   &mysql.Cursor{PerPage: 2, Before: uint64(7)},
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "",
			expectedIds:              []uint64{9, 8},
			numOfAttestations:        10,
			pageInfo:                 &rpc.PageInfo{StartCursor: 9, EndCursor: 8, HasNextPage: false, HasPreviousPage: true},
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID with cursor with before and reach to end",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			cursor:                   &mysql.Cursor{PerPage: 3, Before: uint64(7)},
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "",
			expectedIds:              []uint64{10, 9, 8},
			numOfAttestations:        10,
			pageInfo:                 &rpc.PageInfo{StartCursor: 10, EndCursor: 8, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID with cursor with before and no more data to read",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			cursor:                   &mysql.Cursor{PerPage: 2, Before: uint64(10)},
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "twirp error not_found: no matching attestations found",
			expectedIds:              []uint64{},
			numOfAttestations:        10,
		},
		{
			name:                     "ListAttestationsBySubjectDigest with Subject Digest, Owner ID, Repo ID with cursor with both before and after",
			createArtifactAttReq:     testFixture.createArtifactAttReq,
			getPkgBySubjectDigestReq: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID,
			cursor:                   &mysql.Cursor{PerPage: 2, After: uint64(7), Before: uint64(3)},
			readAuthConfig:           dotcomAuthConfig,
			writeAuthConfig:          dotcomAuthConfig,
			expectedErr:              "twirp error internal: internal error",
			expectedIds:              []uint64{},
			numOfAttestations:        10,
		},
	}

	for _, tc := range testcases {
		server, db, azClient := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithHMACClientIDHeader(t, tc.writeAuthConfig.ClientID)

		// Create the attestation multiple times
		for i := 0; i < tc.numOfAttestations; i++ {
			_, err := twClient.CreateAttestationByOwnerRepository(ctx, tc.createArtifactAttReq)
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		}

		ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.readAuthConfig.ClientID))

		// If a cursor is provided, we need to update the request to include the cursor
		getPkgBySubjectDigestReq := tc.getPkgBySubjectDigestReq
		if tc.cursor != nil {
			perPage := uint32(tc.cursor.PerPage)
			getPkgBySubjectDigestReq = &rpc.ListAttestationsBySubjectDigestRequest{
				SubjectDigest: tc.getPkgBySubjectDigestReq.SubjectDigest,
				OwnerId:       tc.getPkgBySubjectDigestReq.OwnerId,
				RepositoryId:  tc.getPkgBySubjectDigestReq.RepositoryId,
				PerPage:       &perPage,
				Before:        &tc.cursor.Before,
				After:         &tc.cursor.After,
			}
		}
		resp, err := twClient.ListAttestationsBySubjectDigest(ctx, getPkgBySubjectDigestReq)

		if tc.expectedErr != "" {
			assert.Equal(t, err.Error(), tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, resp, fmt.Sprintf("test '%s': should have nil response", tc.name))
		} else {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
			assert.Len(t, resp.Attestations, len(tc.expectedIds), fmt.Sprintf("test '%s': should have %d records", tc.name, len(tc.expectedIds)))
			for i, attestation := range resp.Attestations {
				assert.Equal(t, tc.expectedIds[i], attestation.Id, fmt.Sprintf("test '%s': should have id %d", tc.name, tc.expectedIds[i]))
			}

			// check pageinfo
			assert.Equal(t, tc.pageInfo.StartCursor, resp.PageInfo.StartCursor, fmt.Sprintf("test '%s': should have start cursor %d", tc.name, tc.pageInfo.StartCursor))
			assert.Equal(t, tc.pageInfo.EndCursor, resp.PageInfo.EndCursor, fmt.Sprintf("test '%s': should have end cursor %d", tc.name, tc.pageInfo.EndCursor))
			assert.Equal(t, tc.pageInfo.HasNextPage, resp.PageInfo.HasNextPage, fmt.Sprintf("test '%s': should have has next page %t", tc.name, tc.pageInfo.HasNextPage))
			assert.Equal(t, tc.pageInfo.HasPreviousPage, resp.PageInfo.HasPreviousPage, fmt.Sprintf("test '%s': should have has previous page %t", tc.name, tc.pageInfo.HasPreviousPage))
		}

		cleanUp(t, server, db, azClient)
	}
}

// GitHubAPI: ListAttestationsBySubjectDigest
// when fetching a package's attestations, if none exist it successfully returns an no matching attestations error
func TestGitHubAPIListAttestationsBySubjectDigestNoneShouldBeEmptyResponse(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)

	// test the GetPackageAttestations endpoint
	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	req := &rpc.GetPackageAttestationsRequest{Purl: TestPurl}
	ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID))
	_, err := twClient.GetPackageAttestations(ctx, req)

	assert.Equal(t, err, ErrNoMatchingAttestations, "should return an ErrNoMatchingAttestations error")

	// TODO: remove this half of the test? It seems to be using GitHub API instead of PackageInfoReadAPI
	// test the ListAttestationsBySubjectDigest endpoint
	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twDotcomClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	subjectDigestReq := &rpc.ListAttestationsBySubjectDigestRequest{SubjectDigest: SubjectDigest}

	ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID))
	_, err = twDotcomClient.ListAttestationsBySubjectDigest(ctx, subjectDigestReq)
	assert.Equal(t, err, ErrNoMatchingAttestations, "should return an ErrNoMatchingAttestations error")
}

/*
  GitHubAPI - ListAttestationsByRepositorySummary
	  POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationsByRepositorySummary
*/

// ListAttestationsBySubjectDigestTestCase represents the test case for GitHubAPI/ListAttestationsByRepositorySummary
type listAttestationsByRepositorySummaryTestCase struct {
	name              string
	createAttReq      *rpc.CreateAttestationByOwnerRepositoryRequest
	listAttByRepoReq  *rpc.ListAttestationsByRepositoryRequest
	cursor            *mysql.Cursor
	readAuthConfig    auth.ClientConfig
	writeAuthConfig   auth.ClientConfig
	expectedErr       string
	expectedIds       []uint64
	numOfAttestations int
	pageInfo          *rpc.PageInfo
}

// GitHubAPI: ListAttestationsByRepositorySummary
func TestGitHubAPIListAttestationsByRepositorySummary(t *testing.T) {
	testFixture := newFixtureGitHubAPI(t)
	testcases := []listAttestationsByRepositorySummaryTestCase{
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID without cursor",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{5, 4, 3, 2, 1},
			numOfAttestations: 5,
			pageInfo:          &rpc.PageInfo{StartCursor: 5, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID without cursor but have more",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2},
			numOfAttestations: 31,
			pageInfo:          &rpc.PageInfo{StartCursor: 31, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID with cursor per page 1",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 1},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{10},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 10, EndCursor: 10, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID with cursor per page 2 with after and reach to end",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(3)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{2, 1},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 2, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID with cursor with after and not reach to end",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(4)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{3, 2},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 3, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID with cursor with after and no more data to read",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(1)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "twirp error not_found: no matching attestations found",
			expectedIds:       []uint64{},
			numOfAttestations: 10,
		},
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID with cursor with before and not reach to end",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, Before: uint64(7)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{9, 8},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 9, EndCursor: 8, HasNextPage: false, HasPreviousPage: true},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID with cursor with before and reach to end",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 3, Before: uint64(7)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{10, 9, 8},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 10, EndCursor: 8, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Owner ID, Repo ID with cursor with before and no more data to read",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, Before: uint64(10)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "twirp error not_found: no matching attestations found",
			expectedIds:       []uint64{},
			numOfAttestations: 10,
		},
	}

	// for now we're using the same bundle for each attestation fixture
	summaryData := struct {
		SubjectDigest      string
		PredicateType      string
		CertificateSummary rpc.CertificateSummary
	}{
		SubjectDigest: "sha512:7dc53d7251f012cb36fccff5d4514cf09c1ce0f8c181b857a0db24a0ae60ba82b4a8640149e51b419449f81d9f0c522f8727f482a09a3eb7a5f66b336e1031ba",
		PredicateType: "https://slsa.dev/provenance/v1",
		CertificateSummary: rpc.CertificateSummary{
			Issuer:                              "https://token.actions.githubusercontent.com",
			BuildSignerUri:                      "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
			BuildSignerDigest:                   "d9093d4b3b99d9ee446633ac7074e43cea78c727",
			RunnerEnvironment:                   "github-hosted",
			SourceRepositoryUri:                 "https://github.com/sigstore/sigstore-js",
			SourceRepositoryDigest:              "d9093d4b3b99d9ee446633ac7074e43cea78c727",
			SourceRepositoryRef:                 "refs/heads/main",
			SourceRepositoryIdentifier:          "495574555",
			SourceRepositoryOwnerUri:            "https://github.com/sigstore",
			SourceRepositoryOwnerIdentifier:     "71096353",
			BuildConfigUri:                      "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
			BuildConfigDigest:                   "d9093d4b3b99d9ee446633ac7074e43cea78c727",
			BuildTrigger:                        "push",
			RunInvocationUri:                    "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/attempts/1",
			SourceRepositoryVisibilityAtSigning: "public",
			SubjectAlternativeName: &rpc.SubjectAlternativeName{
				Type:  "URI",
				Value: "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
			},
		},
	}

	for _, tc := range testcases {
		server, db, azClient := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.writeAuthConfig.ClientID))

		// Create the attestation multiple times
		for i := 0; i < tc.numOfAttestations; i++ {
			_, err := twClient.CreateAttestationByOwnerRepository(ctx, tc.createAttReq)
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		}

		ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.readAuthConfig.ClientID))

		// If a cursor is provided, we need to update the request to include the cursor
		listAttByRepoReq := tc.listAttByRepoReq
		if tc.cursor != nil {
			perPage := uint32(tc.cursor.PerPage)
			listAttByRepoReq = &rpc.ListAttestationsByRepositoryRequest{
				OwnerId:      tc.listAttByRepoReq.OwnerId,
				RepositoryId: tc.listAttByRepoReq.RepositoryId,
				PerPage:      &perPage,
				Before:       &tc.cursor.Before,
				After:        &tc.cursor.After,
			}
		}
		resp, err := twClient.ListAttestationsByRepositorySummary(ctx, listAttByRepoReq)

		if tc.expectedErr != "" {
			assert.Equal(t, err.Error(), tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, resp, fmt.Sprintf("test '%s': should have nil response", tc.name))
		} else {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
			assert.Len(t, resp.AttestationSummaries, len(tc.expectedIds), fmt.Sprintf("test '%s': should have %d records", tc.name, len(tc.expectedIds)))
			for i, attestation := range resp.AttestationSummaries {
				assert.Equal(t, tc.expectedIds[i], attestation.Id, fmt.Sprintf("test '%s': should have id %d", tc.name, tc.expectedIds[i]))
				// verify the summary data was serialized correctly
				assert.Equal(t, summaryData.SubjectDigest, attestation.SubjectDigest, fmt.Sprintf("test '%s': SubjectDigest should be %s", tc.name, summaryData.SubjectDigest))
				assert.Equal(t, summaryData.PredicateType, attestation.PredicateType, fmt.Sprintf("test '%s': SubjectDigest should be %s", tc.name, summaryData.PredicateType))
				assert.Equal(t, summaryData.CertificateSummary.Issuer, attestation.CertificateSummary.Issuer, fmt.Sprintf("test '%s': should have issuer %s", tc.name, summaryData.CertificateSummary.Issuer))
				assert.Equal(t, summaryData.CertificateSummary.BuildSignerUri, attestation.CertificateSummary.BuildSignerUri, fmt.Sprintf("test '%s': BuildSignerUri should be %s", tc.name, summaryData.CertificateSummary.BuildSignerUri))
				assert.Equal(t, summaryData.CertificateSummary.BuildSignerDigest, attestation.CertificateSummary.BuildSignerDigest, fmt.Sprintf("test '%s': BuildSignerDigest should be %s", tc.name, summaryData.CertificateSummary.BuildSignerDigest))
				assert.Equal(t, summaryData.CertificateSummary.RunnerEnvironment, attestation.CertificateSummary.RunnerEnvironment, fmt.Sprintf("test '%s': RunnerEnvironment should be %s", tc.name, summaryData.CertificateSummary.RunnerEnvironment))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryUri, attestation.CertificateSummary.SourceRepositoryUri, fmt.Sprintf("test '%s': SourceRepositoryUri should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryUri))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryDigest, attestation.CertificateSummary.SourceRepositoryDigest, fmt.Sprintf("test '%s': SourceRepositoryDigest should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryDigest))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryRef, attestation.CertificateSummary.SourceRepositoryRef, fmt.Sprintf("test '%s': SourceRepositoryRef should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryRef))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryIdentifier, attestation.CertificateSummary.SourceRepositoryIdentifier, fmt.Sprintf("test '%s': SourceRepositoryIdentifier should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryIdentifier))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryOwnerUri, attestation.CertificateSummary.SourceRepositoryOwnerUri, fmt.Sprintf("test '%s': SourceRepositoryOwnerURI should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryOwnerUri))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryOwnerIdentifier, attestation.CertificateSummary.SourceRepositoryOwnerIdentifier, fmt.Sprintf("test '%s': SourceRepositoryOwnerIdentifier should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryOwnerIdentifier))
				assert.Equal(t, summaryData.CertificateSummary.BuildConfigUri, attestation.CertificateSummary.BuildConfigUri, fmt.Sprintf("test '%s': BuildConfigUri should be %s", tc.name, summaryData.CertificateSummary.BuildConfigUri))
				assert.Equal(t, summaryData.CertificateSummary.BuildConfigDigest, attestation.CertificateSummary.BuildConfigDigest, fmt.Sprintf("test '%s': BuildConfigDigest should be %s", tc.name, summaryData.CertificateSummary.BuildConfigDigest))
				assert.Equal(t, summaryData.CertificateSummary.BuildTrigger, attestation.CertificateSummary.BuildTrigger, fmt.Sprintf("test '%s': BuildTrigger should be %s", tc.name, summaryData.CertificateSummary.BuildTrigger))
				assert.Equal(t, summaryData.CertificateSummary.RunInvocationUri, attestation.CertificateSummary.RunInvocationUri, fmt.Sprintf("test '%s': RunInvocationUri should be %s", tc.name, summaryData.CertificateSummary.RunInvocationUri))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryVisibilityAtSigning, attestation.CertificateSummary.SourceRepositoryVisibilityAtSigning, fmt.Sprintf("test '%s': SourceRepositoryVisibilityAtSigning should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryVisibilityAtSigning))
				assert.Equal(t, summaryData.CertificateSummary.SubjectAlternativeName.Value, attestation.CertificateSummary.SubjectAlternativeName.Value, fmt.Sprintf("test '%s': SubjectAlternativeName.Value should be %s", tc.name, summaryData.CertificateSummary.SubjectAlternativeName.Value))
			}
			// check pageinfo
			assert.Equal(t, tc.pageInfo.StartCursor, resp.PageInfo.StartCursor, fmt.Sprintf("test '%s': should have start cursor %d", tc.name, tc.pageInfo.StartCursor))
			assert.Equal(t, tc.pageInfo.EndCursor, resp.PageInfo.EndCursor, fmt.Sprintf("test '%s': should have end cursor %d", tc.name, tc.pageInfo.EndCursor))
			assert.Equal(t, tc.pageInfo.HasNextPage, resp.PageInfo.HasNextPage, fmt.Sprintf("test '%s': should have has next page %t", tc.name, tc.pageInfo.HasNextPage))
			assert.Equal(t, tc.pageInfo.HasPreviousPage, resp.PageInfo.HasPreviousPage, fmt.Sprintf("test '%s': should have has previous page %t", tc.name, tc.pageInfo.HasPreviousPage))
		}

		cleanUp(t, server, db, azClient)
	}
}

/*
  GitHubAPI - GetAttestationSummaryByRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/GetAttestationSummaryByRepository
*/

type getAttestationSummaryByRepositoryTestCase struct {
	name            string
	createAttReq    *rpc.CreateAttestationByOwnerRepositoryRequest
	showAttByIdReq  *rpc.GetAttestationSummaryByRepositoryRequest
	readAuthConfig  auth.ClientConfig
	writeAuthConfig auth.ClientConfig
	expectedErr     string
}

// GitHubAPI: GetAttestationSummaryByRepository
func TestGitHubAPIGetAttestationSummaryByRepository(t *testing.T) {
	testFixture := newFixtureGitHubAPI(t)
	testcases := []getAttestationSummaryByRepositoryTestCase{
		{
			name:            "GetAttestationSummaryByRepository with valid id",
			createAttReq:    testFixture.createArtifactAttReq,
			showAttByIdReq:  testFixture.showAttByIdReq,
			readAuthConfig:  dotcomAuthConfig,
			writeAuthConfig: dotcomAuthConfig,
			expectedErr:     "",
		},
		{
			name:            "GetAttestationSummaryByRepository with invalid id",
			createAttReq:    testFixture.createArtifactAttReq,
			showAttByIdReq:  testFixture.showAttByInvalidIdReq,
			readAuthConfig:  dotcomAuthConfig,
			writeAuthConfig: dotcomAuthConfig,
			expectedErr:     "twirp error not_found: no matching attestations found",
		},
	}

	for _, tc := range testcases {
		server, db, azClient := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.writeAuthConfig.ClientID))

		// Create the attestation
		_, err := twClient.CreateAttestationByOwnerRepository(ctx, tc.createAttReq)
		assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))

		ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.readAuthConfig.ClientID))

		showAttByIdReq := tc.showAttByIdReq
		perPage := uint32(1)
		listAttByRepoReq := &rpc.ListAttestationsByRepositoryRequest{
			OwnerId:      *showAttByIdReq.OwnerId,
			RepositoryId: *showAttByIdReq.RepositoryId,
			PerPage:      &perPage,
		}
		// Get the first attestation so we can get its ID
		listAttestationsResp, err := twClient.ListAttestationsByRepositorySummary(ctx, listAttByRepoReq)
		// 0 is special case here, it means we want to the id of the latest created attestation
		if showAttByIdReq.AttestationId == 0 {
			showAttByIdReq.AttestationId = listAttestationsResp.AttestationSummaries[0].Id
		}

		showAttReq := &rpc.GetAttestationSummaryByRepositoryRequest{
			AttestationId: showAttByIdReq.AttestationId,
			OwnerId:       showAttByIdReq.OwnerId,
			RepositoryId:  showAttByIdReq.RepositoryId,
		}
		showAttestationResponse, err := twClient.GetAttestationSummaryByRepository(ctx, showAttReq)

		if tc.expectedErr != "" {
			assert.Equal(t, err.Error(), tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, showAttestationResponse, fmt.Sprintf("test '%s': should have nil response", tc.name))
		} else {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
			attestation := listAttestationsResp.AttestationSummaries[0]
			showAtt := showAttestationResponse

			// AttestationSummary which is primarily built from an AttestationRecord
			assert.Equal(t, showAtt.AttestationSummary.Id, attestation.Id, fmt.Sprintf("test '%s': should have expected id", tc.name))
			assert.Equal(t, showAtt.AttestationSummary.OwnerId, attestation.OwnerId, fmt.Sprintf("test '%s': should have expected owner_id", tc.name))
			assert.Equal(t, showAtt.AttestationSummary.RepositoryId, attestation.RepositoryId, fmt.Sprintf("test '%s': should have expected repository_id", tc.name))
			assert.Equal(t, showAtt.AttestationSummary.CreatedAt, attestation.CreatedAt, fmt.Sprintf("test '%s': should have expected created_at", tc.name))
			assert.Equal(t, showAtt.AttestationSummary.PredicateType, attestation.PredicateType, fmt.Sprintf("test '%s': should have expected predicate_type", tc.name))
		}

		cleanUp(t, server, db, azClient)
	}
}

/*
  GitHubAPI - GetAttestationByRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/GetAttestationByRepository
*/

type getAttestationByRepositoryTestCase struct {
	name            string
	createAttReq    *rpc.CreateAttestationByOwnerRepositoryRequest
	getAttByIdReq   *rpc.GetAttestationByRepositoryRequest
	readAuthConfig  auth.ClientConfig
	writeAuthConfig auth.ClientConfig
	expectedErr     string
}

// GitHubAPI: GetAttestationByRepository
func TestGitHubAPIGetAttestationByRepository(t *testing.T) {
	testFixture := newFixtureGitHubAPI(t)
	testcases := []getAttestationByRepositoryTestCase{
		{
			name:            "GetAttestationByRepository with valid id",
			createAttReq:    testFixture.createArtifactAttReq,
			getAttByIdReq:   testFixture.getAttByIdReq,
			readAuthConfig:  dotcomAuthConfig,
			writeAuthConfig: dotcomAuthConfig,
			expectedErr:     "",
		},
		{
			name:            "GetAttestationByRepository with invalid id",
			createAttReq:    testFixture.createArtifactAttReq,
			getAttByIdReq:   testFixture.getAttByInvalidIdReq,
			readAuthConfig:  dotcomAuthConfig,
			writeAuthConfig: dotcomAuthConfig,
			expectedErr:     "twirp error not_found: no attestation for given (purl, predicateType) exists",
		},
	}

	for _, tc := range testcases {
		server, db, azClient := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)

		ctx := createCtxWithHMACClientIDHeader(t, tc.writeAuthConfig.ClientID)

		// Create the attestation
		_, err := twClient.CreateAttestationByOwnerRepository(ctx, tc.createAttReq)
		assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.readAuthConfig.ClientID))

		getAttByIdReq := tc.getAttByIdReq
		perPage := uint32(1)
		listAttByRepoReq := &rpc.ListAttestationsByRepositoryRequest{
			OwnerId:      *getAttByIdReq.OwnerId,
			RepositoryId: *getAttByIdReq.RepositoryId,
			PerPage:      &perPage,
		}
		// Get the first attestation so we can get its ID
		attestationsResp, err := twClient.ListAttestationsByRepositorySummary(ctx, listAttByRepoReq)
		// 0 is special case here, it means we want to the id of the latest created attestation
		if getAttByIdReq.AttestationId == 0 {
			getAttByIdReq.AttestationId = attestationsResp.AttestationSummaries[0].Id
		}
		getAttReq := &rpc.GetAttestationByRepositoryRequest{
			AttestationId: getAttByIdReq.AttestationId,
			OwnerId:       getAttByIdReq.OwnerId,
			RepositoryId:  getAttByIdReq.RepositoryId,
		}
		resp, err := twClient.GetAttestationByRepository(ctx, getAttReq)

		if tc.expectedErr != "" {
			assert.Equal(t, err.Error(), tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, resp, fmt.Sprintf("test '%s': should have nil response", tc.name))
		} else {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error: %v", tc.name, err))
			fmt.Println(resp.Attestation)
			assert.Equal(t, resp.Attestation.PredicateType, "https://slsa.dev/provenance/v1", fmt.Sprintf("test '%s': should have expected predicate type", tc.name))
			assert.Equal(t, resp.Attestation.Id, attestationsResp.AttestationSummaries[0].Id, fmt.Sprintf("test '%s': should have expected id", tc.name))
			assert.NotZero(t, resp.Attestation.SignedAccessSignatureUrl, fmt.Sprintf("test '%s': should return a valid SAS URL", tc.name))
		}

		cleanUp(t, server, db, azClient)
	}
}

/*
  GitHubAPI - ListAttestationSummariesByRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationSummariesByRepository
*/

// listAttestationSummariesByRepositoryTestCase represents the test case for GitHubAPI: ListAttestationSummariesByRepository
type listAttestationSummariesByRepositoryTestCase struct {
	name              string
	createAttReq      *rpc.CreateAttestationByOwnerRepositoryRequest
	listAttByRepoReq  *rpc.ListAttestationsByRepositoryRequest
	cursor            *mysql.Cursor
	readAuthConfig    auth.ClientConfig
	writeAuthConfig   auth.ClientConfig
	expectedErr       string
	expectedIds       []uint64
	numOfAttestations int
	pageInfo          *rpc.PageInfo
}

// GitHubAPI: ListAttestationsByRepositorySummary
func TestGitHubAPIListAttestationSummariesByRepository(t *testing.T) {
	testFixture := newFixtureGitHubAPI(t)
	testcases := []listAttestationSummariesByRepositoryTestCase{
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID without cursor",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{5, 4, 3, 2, 1},
			numOfAttestations: 5,
			pageInfo:          &rpc.PageInfo{StartCursor: 5, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID without cursor but have more",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2},
			numOfAttestations: 31,
			pageInfo:          &rpc.PageInfo{StartCursor: 31, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID with cursor per page 1",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 1},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{10},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 10, EndCursor: 10, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID with cursor per page 2 with after and reach to end",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(3)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{2, 1},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 2, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID with cursor with after and not reach to end",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(4)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{3, 2},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 3, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID with cursor with after and no more data to read",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(1)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "twirp error not_found: no matching attestations found",
			expectedIds:       []uint64{},
			numOfAttestations: 10,
		},
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID with cursor with before and not reach to end",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, Before: uint64(7)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{9, 8},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 9, EndCursor: 8, HasNextPage: false, HasPreviousPage: true},
		},
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID with cursor with before and reach to end",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 3, Before: uint64(7)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{10, 9, 8},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 10, EndCursor: 8, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListAttestationSummariesByRepository with Owner ID, Repo ID with cursor with before and no more data to read",
			createAttReq:      testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, Before: uint64(10)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "twirp error not_found: no matching attestations found",
			expectedIds:       []uint64{},
			numOfAttestations: 10,
		},
	}

	// for now we're using the same bundle for each attestation fixture
	summaryData := struct {
		SubjectDigest      string
		PredicateType      string
		CertificateSummary rpc.CertificateSummary
	}{
		SubjectDigest: "sha512:7dc53d7251f012cb36fccff5d4514cf09c1ce0f8c181b857a0db24a0ae60ba82b4a8640149e51b419449f81d9f0c522f8727f482a09a3eb7a5f66b336e1031ba",
		PredicateType: "https://slsa.dev/provenance/v1",
		CertificateSummary: rpc.CertificateSummary{
			Issuer:                              "https://token.actions.githubusercontent.com",
			BuildSignerUri:                      "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
			BuildSignerDigest:                   "d9093d4b3b99d9ee446633ac7074e43cea78c727",
			RunnerEnvironment:                   "github-hosted",
			SourceRepositoryUri:                 "https://github.com/sigstore/sigstore-js",
			SourceRepositoryDigest:              "d9093d4b3b99d9ee446633ac7074e43cea78c727",
			SourceRepositoryRef:                 "refs/heads/main",
			SourceRepositoryIdentifier:          "495574555",
			SourceRepositoryOwnerUri:            "https://github.com/sigstore",
			SourceRepositoryOwnerIdentifier:     "71096353",
			BuildConfigUri:                      "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
			BuildConfigDigest:                   "d9093d4b3b99d9ee446633ac7074e43cea78c727",
			BuildTrigger:                        "push",
			RunInvocationUri:                    "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/attempts/1",
			SourceRepositoryVisibilityAtSigning: "public",
			SubjectAlternativeName: &rpc.SubjectAlternativeName{
				Type:  "URI",
				Value: "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
			},
		},
	}

	for _, tc := range testcases {
		server, db, azClient := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.writeAuthConfig.ClientID))

		// Create the attestation multiple times
		for i := 0; i < tc.numOfAttestations; i++ {
			_, err := twClient.CreateAttestationByOwnerRepository(ctx, tc.createAttReq)
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		}

		ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.readAuthConfig.ClientID))

		// If a cursor is provided, we need to update the request to include the cursor
		listAttByRepoReq := tc.listAttByRepoReq
		if tc.cursor != nil {
			perPage := uint32(tc.cursor.PerPage)
			listAttByRepoReq = &rpc.ListAttestationsByRepositoryRequest{
				OwnerId:      tc.listAttByRepoReq.OwnerId,
				RepositoryId: tc.listAttByRepoReq.RepositoryId,
				PerPage:      &perPage,
				Before:       &tc.cursor.Before,
				After:        &tc.cursor.After,
			}
		}
		resp, err := twClient.ListAttestationSummariesByRepository(ctx, listAttByRepoReq)

		if tc.expectedErr != "" {
			assert.Equal(t, err.Error(), tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, resp, fmt.Sprintf("test '%s': should have nil response", tc.name))
		} else {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
			assert.Len(t, resp.AttestationSummaries, len(tc.expectedIds), fmt.Sprintf("test '%s': should have %d records", tc.name, len(tc.expectedIds)))
			for i, attestation := range resp.AttestationSummaries {
				assert.Equal(t, tc.expectedIds[i], attestation.Id, fmt.Sprintf("test '%s': should have id %d", tc.name, tc.expectedIds[i]))
				// verify the summary data was serialized correctly
				assert.Equal(t, summaryData.PredicateType, attestation.PredicateType, fmt.Sprintf("test '%s': SubjectDigest should be %s", tc.name, summaryData.PredicateType))
				assert.Equal(t, summaryData.CertificateSummary.BuildSignerUri, attestation.CertificateSummary.BuildSignerUri, fmt.Sprintf("test '%s': BuildSignerUri should be %s", tc.name, summaryData.CertificateSummary.BuildSignerUri))
				assert.Equal(t, summaryData.CertificateSummary.BuildSignerDigest, attestation.CertificateSummary.BuildSignerDigest, fmt.Sprintf("test '%s': BuildSignerDigest should be %s", tc.name, summaryData.CertificateSummary.BuildSignerDigest))
				assert.Equal(t, summaryData.CertificateSummary.RunnerEnvironment, attestation.CertificateSummary.RunnerEnvironment, fmt.Sprintf("test '%s': RunnerEnvironment should be %s", tc.name, summaryData.CertificateSummary.RunnerEnvironment))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryUri, attestation.CertificateSummary.SourceRepositoryUri, fmt.Sprintf("test '%s': SourceRepositoryUri should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryUri))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryDigest, attestation.CertificateSummary.SourceRepositoryDigest, fmt.Sprintf("test '%s': SourceRepositoryDigest should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryDigest))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryRef, attestation.CertificateSummary.SourceRepositoryRef, fmt.Sprintf("test '%s': SourceRepositoryRef should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryRef))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryIdentifier, attestation.CertificateSummary.SourceRepositoryIdentifier, fmt.Sprintf("test '%s': SourceRepositoryIdentifier should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryIdentifier))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryOwnerUri, attestation.CertificateSummary.SourceRepositoryOwnerUri, fmt.Sprintf("test '%s': SourceRepositoryOwnerURI should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryOwnerUri))
				assert.Equal(t, summaryData.CertificateSummary.SourceRepositoryOwnerIdentifier, attestation.CertificateSummary.SourceRepositoryOwnerIdentifier, fmt.Sprintf("test '%s': SourceRepositoryOwnerIdentifier should be %s", tc.name, summaryData.CertificateSummary.SourceRepositoryOwnerIdentifier))
				assert.Equal(t, summaryData.CertificateSummary.BuildConfigUri, attestation.CertificateSummary.BuildConfigUri, fmt.Sprintf("test '%s': BuildConfigUri should be %s", tc.name, summaryData.CertificateSummary.BuildConfigUri))
				assert.Equal(t, summaryData.CertificateSummary.BuildConfigDigest, attestation.CertificateSummary.BuildConfigDigest, fmt.Sprintf("test '%s': BuildConfigDigest should be %s", tc.name, summaryData.CertificateSummary.BuildConfigDigest))
				assert.Equal(t, summaryData.CertificateSummary.BuildTrigger, attestation.CertificateSummary.BuildTrigger, fmt.Sprintf("test '%s': BuildTrigger should be %s", tc.name, summaryData.CertificateSummary.BuildTrigger))
				assert.Equal(t, summaryData.CertificateSummary.RunInvocationUri, attestation.CertificateSummary.RunInvocationUri, fmt.Sprintf("test '%s': RunInvocationUri should be %s", tc.name, summaryData.CertificateSummary.RunInvocationUri))
			}
			// check pageinfo
			assert.Equal(t, tc.pageInfo.StartCursor, resp.PageInfo.StartCursor, fmt.Sprintf("test '%s': should have start cursor %d, was %d", tc.name, tc.pageInfo.StartCursor, resp.PageInfo.StartCursor))
			assert.Equal(t, tc.pageInfo.EndCursor, resp.PageInfo.EndCursor, fmt.Sprintf("test '%s': should have end cursor %d, was %d", tc.name, tc.pageInfo.EndCursor, resp.PageInfo.EndCursor))
			assert.Equal(t, tc.pageInfo.HasNextPage, resp.PageInfo.HasNextPage, fmt.Sprintf("test '%s': should have has next page %t", tc.name, tc.pageInfo.HasNextPage))
			assert.Equal(t, tc.pageInfo.HasPreviousPage, resp.PageInfo.HasPreviousPage, fmt.Sprintf("test '%s': should have has previous page %t", tc.name, tc.pageInfo.HasPreviousPage))
		}

		cleanUp(t, server, db, azClient)
	}
}

/*
  GitHubAPI - ListAttestationsByRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationsByRepository
*/

// listAttestationsByRepositoryTestCase represents the test case for GitHubAPI: ListAttestationsByRepository
type listAttestationsByRepositoryTestCase struct {
	name              string
	createAttReq      *rpc.CreateAttestationByOwnerRepositoryRequest
	listAttByRepoReq  *rpc.ListAttestationsByRepositoryRequest
	cursor            *mysql.Cursor
	readAuthConfig    auth.ClientConfig
	writeAuthConfig   auth.ClientConfig
	expectedErr       string
	expectedIds       []uint64
	numOfAttestations int
	pageInfo          *rpc.PageInfo
}

// GitHubAPI: ListAttestationsByRepository
func TestGitHubReadAPIListAttestationsByRepository(t *testing.T) {
	testFixture := newFixtureGitHubAPI(t)
	testcases := []listAttestationsByRepositoryTestCase{
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID without cursor",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{5, 4, 3, 2, 1},
			numOfAttestations: 5,
			pageInfo:          &rpc.PageInfo{StartCursor: 5, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID without cursor but have more",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2},
			numOfAttestations: 31,
			pageInfo:          &rpc.PageInfo{StartCursor: 31, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID with cursor per page 1",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 1},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{10},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 10, EndCursor: 10, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID with cursor per page 2 with after and reach to end",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(3)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{2, 1},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 2, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID with cursor with after and not reach to end",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(4)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{3, 2},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 3, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID with cursor with after and no more data to read",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, After: uint64(1)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "twirp error not_found: no matching attestations found",
			expectedIds:       []uint64{},
			numOfAttestations: 10,
		},
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID with cursor with before and not reach to end",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, Before: uint64(7)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{9, 8},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 9, EndCursor: 8, HasNextPage: false, HasPreviousPage: true},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID with cursor with before and reach to end",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 3, Before: uint64(7)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "",
			expectedIds:       []uint64{10, 9, 8},
			numOfAttestations: 10,
			pageInfo:          &rpc.PageInfo{StartCursor: 10, EndCursor: 8, HasNextPage: false, HasPreviousPage: false},
		},
		{
			name:              "ListArtifactAttestationsByRepository with Subject Digest, Owner ID, Repo ID with cursor with before and no more data to read",
			createAttReq:      testFixture.createArtifactAttReq,
			listAttByRepoReq:  testFixture.listAttByRepoReq,
			cursor:            &mysql.Cursor{PerPage: 2, Before: uint64(10)},
			readAuthConfig:    dotcomAuthConfig,
			writeAuthConfig:   dotcomAuthConfig,
			expectedErr:       "twirp error not_found: no matching attestations found",
			expectedIds:       []uint64{},
			numOfAttestations: 10,
		},
	}

	for _, tc := range testcases {
		server, db, azClient := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)

		ctx := createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.writeAuthConfig.ClientID))

		// Create the attestation multiple times
		for i := 0; i < tc.numOfAttestations; i++ {
			_, err := twClient.CreateAttestationByOwnerRepository(ctx, tc.createAttReq)
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		}

		ctx = createCtxWithTestClientIpAddr(createCtxWithHMACClientIDHeader(t, tc.readAuthConfig.ClientID))

		// If a cursor is provided, we need to update the request to include the cursor
		listAttByRepoReq := tc.listAttByRepoReq
		if tc.cursor != nil {
			perPage := uint32(tc.cursor.PerPage)
			listAttByRepoReq = &rpc.ListAttestationsByRepositoryRequest{
				OwnerId:      tc.listAttByRepoReq.OwnerId,
				RepositoryId: tc.listAttByRepoReq.RepositoryId,
				PerPage:      &perPage,
				Before:       &tc.cursor.Before,
				After:        &tc.cursor.After,
			}
		}
		resp, err := twClient.ListAttestationsByRepositorySummary(ctx, listAttByRepoReq)

		if tc.expectedErr != "" {
			assert.Equal(t, err.Error(), tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, resp, fmt.Sprintf("test '%s': should have nil response", tc.name))
		} else {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
			assert.Len(t, resp.AttestationSummaries, len(tc.expectedIds), fmt.Sprintf("test '%s': should have %d records", tc.name, len(tc.expectedIds)))
			for i, attestation := range resp.AttestationSummaries {
				assert.Equal(t, tc.expectedIds[i], attestation.Id, fmt.Sprintf("test '%s': should have id %d", tc.name, tc.expectedIds[i]))
			}
			// check pageinfo
			assert.Equal(t, tc.pageInfo.StartCursor, resp.PageInfo.StartCursor, fmt.Sprintf("test '%s': should have start cursor %d", tc.name, tc.pageInfo.StartCursor))
			assert.Equal(t, tc.pageInfo.EndCursor, resp.PageInfo.EndCursor, fmt.Sprintf("test '%s': should have end cursor %d", tc.name, tc.pageInfo.EndCursor))
			assert.Equal(t, tc.pageInfo.HasNextPage, resp.PageInfo.HasNextPage, fmt.Sprintf("test '%s': should have has next page %t", tc.name, tc.pageInfo.HasNextPage))
			assert.Equal(t, tc.pageInfo.HasPreviousPage, resp.PageInfo.HasPreviousPage, fmt.Sprintf("test '%s': should have has previous page %t", tc.name, tc.pageInfo.HasPreviousPage))
		}

		cleanUp(t, server, db, azClient)
	}
}
