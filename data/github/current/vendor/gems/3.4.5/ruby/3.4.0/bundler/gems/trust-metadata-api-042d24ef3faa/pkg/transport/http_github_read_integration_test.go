//go:build integration

package transport

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	twcauth "github.com/github/go-twirp/v2/client/auth"
	"github.com/github/trust-metadata-api/pkg/attestation"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
	v1 "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
)

// fixture represents the protobuf rpc data used for testing
type fixtureReadGitHubAPI struct {
	// GitHubAPI/CreateAttestationByOwnerRepository
	createPkgAttReqSigstore300WithOwnerRepoID *rpc.CreateAttestationByOwnerRepositoryRequest
	createArtifactAttReq                      *rpc.CreateAttestationByOwnerRepositoryRequest
	// GitHubAPI/GetAttestationByRepository
	getAttByIdReq        *rpc.GetAttestationByRepositoryRequest
	getAttByInvalidIdReq *rpc.GetAttestationByRepositoryRequest
	// GitHubAPI/ListAttestationsBySubjectDigest
	getPkgBySubjectDigestReqWithOwnerRepoID *rpc.ListAttestationsBySubjectDigestRequest
	// GitHubAPI/ListAttestationsByRepository
	listAttByRepoReq *rpc.ListAttestationsByRepositoryRequest
	// GitHubAPI/GetAttestationSummaryByRepository
	showAttByIdReq        *rpc.GetAttestationSummaryByRepositoryRequest
	showAttByInvalidIdReq *rpc.GetAttestationSummaryByRepositoryRequest
}

// newFixtureGitHubAPI constructs a new fixtureGitHubAPI
func newFixtureReadGitHubAPI(t *testing.T) *fixtureReadGitHubAPI {
	ownerID, repoID := uint64(42), uint64(12345)

	return &fixtureReadGitHubAPI{
		// GitHubAPI/ListAttestationsByRepository
		listAttByRepoReq: &rpc.ListAttestationsByRepositoryRequest{
			OwnerId:      ownerID,
			RepositoryId: repoID,
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

type listAttestationsTestCase struct {
	name              string
	cursor            *mysql.Cursor
	expectedErr       string
	expectedIds       []uint64
	numOfAttestations int
	pageInfo          *rpc.PageInfo
}

// This set of test cases can be used to test that methods work as expected
// with page info and cursors
var listAttestationsWithPageInfoTestcases = []listAttestationsTestCase{
	{
		name:              "with Subject Digest, Owner ID, Repo ID without cursor",
		expectedErr:       "",
		expectedIds:       []uint64{5, 4, 3, 2, 1},
		numOfAttestations: 5,
		pageInfo:          &rpc.PageInfo{StartCursor: 5, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID without cursor but have more",
		expectedErr:       "",
		expectedIds:       []uint64{31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2},
		numOfAttestations: 31,
		pageInfo:          &rpc.PageInfo{StartCursor: 31, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID with cursor per page 1",
		cursor:            &mysql.Cursor{PerPage: 1},
		expectedErr:       "",
		expectedIds:       []uint64{10},
		numOfAttestations: 10,
		pageInfo:          &rpc.PageInfo{StartCursor: 10, EndCursor: 10, HasNextPage: true, HasPreviousPage: false},
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID with cursor per page 2 with after and reach to end",
		cursor:            &mysql.Cursor{PerPage: 2, After: uint64(3)},
		expectedErr:       "",
		expectedIds:       []uint64{2, 1},
		numOfAttestations: 10,
		pageInfo:          &rpc.PageInfo{StartCursor: 2, EndCursor: 1, HasNextPage: false, HasPreviousPage: false},
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID with cursor with after and not reach to end",
		cursor:            &mysql.Cursor{PerPage: 2, After: uint64(4)},
		expectedErr:       "",
		expectedIds:       []uint64{3, 2},
		numOfAttestations: 10,
		pageInfo:          &rpc.PageInfo{StartCursor: 3, EndCursor: 2, HasNextPage: true, HasPreviousPage: false},
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID with cursor with after and no more data to read",
		cursor:            &mysql.Cursor{PerPage: 2, After: uint64(1)},
		expectedErr:       "twirp error not_found: no matching attestations found",
		expectedIds:       []uint64{},
		numOfAttestations: 10,
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID with cursor with before and not reach to end",
		cursor:            &mysql.Cursor{PerPage: 2, Before: uint64(7)},
		expectedErr:       "",
		expectedIds:       []uint64{9, 8},
		numOfAttestations: 10,
		pageInfo:          &rpc.PageInfo{StartCursor: 9, EndCursor: 8, HasNextPage: false, HasPreviousPage: true},
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID with cursor with before and reach to end",
		cursor:            &mysql.Cursor{PerPage: 3, Before: uint64(7)},
		expectedErr:       "",
		expectedIds:       []uint64{10, 9, 8},
		numOfAttestations: 10,
		pageInfo:          &rpc.PageInfo{StartCursor: 10, EndCursor: 8, HasNextPage: false, HasPreviousPage: false},
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID with cursor with before and no more data to read",
		cursor:            &mysql.Cursor{PerPage: 2, Before: uint64(10)},
		expectedErr:       "twirp error not_found: no matching attestations found",
		expectedIds:       []uint64{},
		numOfAttestations: 10,
	},
	{
		name:              "with Subject Digest, Owner ID, Repo ID with cursor with both before and after",
		cursor:            &mysql.Cursor{PerPage: 2, After: uint64(7), Before: uint64(3)},
		expectedErr:       "twirp error invalid_argument: cannot set both After and Before",
		expectedIds:       []uint64{},
		numOfAttestations: 10,
	},
}

type predicateFilterTestCase struct {
	name                     string
	predicateType            string
	expectedAttestationCount int
	errMessage               string
}

var predicateFilterTestCases = []predicateFilterTestCase{
	{
		name:                     "filter by provenance predicate type",
		predicateType:            "provenance",
		expectedAttestationCount: 1,
	},
	{
		name:                     "filter by sbom predicate type",
		predicateType:            "sbom",
		expectedAttestationCount: 1,
	},
	{
		name:                     "no filtering",
		predicateType:            "",
		expectedAttestationCount: 2,
	},
	{
		name:                     "filter by valid freeform predicate type",
		predicateType:            "https://mydev.org/someDocument/v1",
		expectedAttestationCount: 0,
		errMessage:               "twirp error not_found: no matching attestations found",
	},
	{
		name:                     "filter by invalid freeform predicate type",
		predicateType:            "https://@@@mydev.org/someDocument/v1",
		expectedAttestationCount: 0,
		errMessage:               "twirp error invalid_argument: predicate_type invalid predicate type provided",
	},
}

/*
	GitHubAPI - DeleteAttestationsByID
		POST /twirp/github.trust_metadata_api.GitHubAPI/DeleteAttestationsByID
*/

func TestGitHubAPIDeleteAttestationsByID(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

	// Create attestations with GitHub bundles
	ownerID, repoID := uint64(42), uint64(12345)
	for _, bundle := range []*v1.Bundle{data.SigstoreBundleAttestDemoProvenance(t), data.SigstoreBundleAttestDemoSBOM(t)} {
		createReq := &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       bundle,
			OwnerId:      ownerID,
			RepositoryId: repoID,
		}
		_, err := twClient.CreateAttestationByOwnerRepository(ctx, createReq)
		assert.NoError(t, err)
	}

	perPage := uint32(30)
	getReq := &rpc.ListAttestationsBySubjectDigestRequest{
		SubjectDigest: data.AttestDemoSubjectDigest,
		OwnerId:       ownerID,
		RepositoryId:  &repoID,
		PerPage:       &perPage,
	}

	// First successfully list the newly created attestation records
	getResp, err := twClient.ListAttestationsBySubjectDigest(ctx, getReq)
	assert.NoError(t, err)
	assert.Len(t, getResp.Attestations, 2)

	// Then delete the records
	deleteReq := &rpc.DeleteAttestationsByIDRequest{
		AttestationIds: []uint64{getResp.Attestations[0].Id, getResp.Attestations[1].Id},
	}
	deleteResp, err := twClient.DeleteAttestationsByID(ctx, deleteReq)
	assert.NoError(t, err)
	assert.NotNil(t, deleteResp)

	// Finally check that the records can no longer be returned
	getResp, err = twClient.ListAttestationsBySubjectDigest(ctx, getReq)
	assert.Equal(t, err, ErrNoMatchingAttestations)
	assert.Nil(t, getResp)
}

func TestGitHubAPIDeleteAttestationsByID_NoAttestationIDs(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

	// Try to make a request with no attestation IDs
	deleteReq := &rpc.DeleteAttestationsByIDRequest{
		AttestationIds: []uint64{},
	}
	deleteResp, err := twClient.DeleteAttestationsByID(ctx, deleteReq)
	assert.ErrorContains(t, err, "twirp error invalid_argument: attestation_ids no attestation IDs provided")
	assert.Nil(t, deleteResp)
}

func TestGitHubAPIDeleteAttestationsByID_TooManyAttestationIDs(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

	// Try to make a request with no attestation IDs
	deleteReq := &rpc.DeleteAttestationsByIDRequest{
		AttestationIds: make([]uint64, attestation.SubjectLimit+1),
	}
	deleteResp, err := twClient.DeleteAttestationsByID(ctx, deleteReq)
	assert.ErrorContains(t, err, fmt.Sprintf("twirp error invalid_argument: attestation_ids too many attestation IDs provided, limit is %d", attestation.SubjectLimit))
	assert.Nil(t, deleteResp)
}

/*
  GitHubAPI - ListAttestationsBySubjectDigest
	  POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationsBySubjectDigest
*/

// GitHubAPI: ListAttestationsBySubjectDigest
// when fetching a package's attestations, if we provide a malformed subject digest we get an error
func TestGitHubAPIMalformedSubjectDigest(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	req := &rpc.ListAttestationsBySubjectDigestRequest{SubjectDigest: "12312"}
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID)

	resp, err := twClient.ListAttestationsBySubjectDigest(ctx, req)

	assert.Error(t, err)
	assert.Nil(t, resp)
}

// GitHubAPI: ListAttestationsBySubjectDigest
func TestGitHubAPIListAttestationsBySubjectDigest(t *testing.T) {
	testFixture := newFixtureReadGitHubAPI(t)
	for _, tc := range listAttestationsWithPageInfoTestcases {
		server, _, cleanUp := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// Create the attestation multiple times
		for i := 0; i < tc.numOfAttestations; i++ {
			_, err := twClient.CreateAttestationByOwnerRepository(ctx, testFixture.createArtifactAttReq)
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		}

		ctx = createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// If a cursor is provided, we need to update the request to include the cursor
		getPkgBySubjectDigestReq := testFixture.getPkgBySubjectDigestReqWithOwnerRepoID
		if tc.cursor != nil {
			perPage := uint32(tc.cursor.PerPage)
			getPkgBySubjectDigestReq = &rpc.ListAttestationsBySubjectDigestRequest{
				SubjectDigest: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.SubjectDigest,
				OwnerId:       testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.OwnerId,
				RepositoryId:  testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.RepositoryId,
				PerPage:       &perPage,
				Before:        &tc.cursor.Before,
				After:         &tc.cursor.After,
			}
		}
		resp, err := twClient.ListAttestationsBySubjectDigest(ctx, getPkgBySubjectDigestReq)

		if tc.expectedErr != "" {
			assert.ErrorContains(t, err, tc.expectedErr)
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

		cleanUp(t)
	}
}

func TestGitHubAPIListAttestationsBySubjectDigest_GitHubBundles_PredicateTypeFiltering(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

	// Create attestations with GitHub bundles
	bundles := []*v1.Bundle{data.SigstoreBundleAttestDemoProvenance(t), data.SigstoreBundleAttestDemoSBOM(t)}
	ownerID, repoID := uint64(42), uint64(12345)
	for _, bundle := range bundles {
		createReq := &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       bundle,
			OwnerId:      ownerID,
			RepositoryId: repoID,
		}
		_, err := twClient.CreateAttestationByOwnerRepository(ctx, createReq)
		assert.NoError(t, err)
	}

	for _, tc := range predicateFilterTestCases {
		perPage := uint32(30)
		getReq := &rpc.ListAttestationsBySubjectDigestRequest{
			SubjectDigest: data.AttestDemoSubjectDigest,
			OwnerId:       ownerID,
			RepositoryId:  &repoID,
			PerPage:       &perPage,
			PredicateType: &tc.predicateType,
		}

		resp, err := twClient.ListAttestationsBySubjectDigest(ctx, getReq)
		if tc.errMessage != "" {
			assert.ErrorContains(t, err, tc.errMessage, tc.name)
			assert.Nil(t, resp, tc.name)
		} else {
			assert.NoError(t, err, tc.name)
			assert.Len(t, resp.Attestations, tc.expectedAttestationCount, tc.name)
		}
	}
}

func TestGitHubAPIListAttestationsBySubjectDigest_BatchSubjectDigests(t *testing.T) {
	testFixture := newFixtureReadGitHubAPI(t)
	for _, tc := range listAttestationsWithPageInfoTestcases {
		server, _, cleanUp := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// Create the attestation multiple times
		for i := 0; i < tc.numOfAttestations; i++ {
			_, err := twClient.CreateAttestationByOwnerRepository(ctx, testFixture.createArtifactAttReq)
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		}

		ctx = createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// If a cursor is provided, we need to update the request to include the cursor
		getPkgBySubjectDigestReq := testFixture.getPkgBySubjectDigestReqWithOwnerRepoID
		if tc.cursor != nil {
			perPage := uint32(tc.cursor.PerPage)
			getPkgBySubjectDigestReq = &rpc.ListAttestationsBySubjectDigestRequest{
				SubjectDigests: []string{testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.SubjectDigest, testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.SubjectDigest},
				OwnerId:        testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.OwnerId,
				RepositoryId:   testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.RepositoryId,
				PerPage:        &perPage,
				Before:         &tc.cursor.Before,
				After:          &tc.cursor.After,
			}
		}
		resp, err := twClient.ListAttestationsBySubjectDigest(ctx, getPkgBySubjectDigestReq)

		if tc.expectedErr != "" {
			assert.ErrorContains(t, err, tc.expectedErr)
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

		cleanUp(t)
	}
}

// GitHubAPI: ListAttestationsBySubjectDigest
// when fetching a package's attestations, if none exist it successfully returns and no matching attestations error
func TestGitHubAPIListAttestationsBySubjectDigestNoneShouldBeEmptyResponse(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	// test the GetPackageAttestations endpoint
	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.PkgRead[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewPackageInfoReadAPIJSONClient(server.URL, client)
	req := &rpc.GetPackageAttestationsRequest{Purl: TestPurl}
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgRead[0].ClientID)
	_, err := twClient.GetPackageAttestations(ctx, req)

	assert.Equal(t, err, ErrNoMatchingAttestations, "should return an ErrNoMatchingAttestations error")

	// TODO: remove this half of the test? It seems to be using GitHub API instead of PackageInfoReadAPI
	// test the ListAttestationsBySubjectDigest endpoint
	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twDotcomClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	subjectDigestReq := &rpc.ListAttestationsBySubjectDigestRequest{SubjectDigest: SubjectDigest}

	ctx = createCtxWithHMACClientIDHeader(t, testHMACConfig.Dotcom[0].ClientID)
	_, err = twDotcomClient.ListAttestationsBySubjectDigest(ctx, subjectDigestReq)
	assert.Equal(t, err, ErrNoMatchingAttestations, "should return an ErrNoMatchingAttestations error")
}

// GitHubAPI: ListAttestationsBySubjectDigest
// the method should return an error when provided invalid subject digest arguments
func TestGitHubAPIListAttestationsBySubjectDigest_InvalidArgs(t *testing.T) {
	testFixture := newFixtureReadGitHubAPI(t)
	testcases := []struct {
		name    string
		request *rpc.ListAttestationsBySubjectDigestRequest
		err     string
	}{
		{
			name: "No subject_digest or subject_digests args provided",
			request: &rpc.ListAttestationsBySubjectDigestRequest{
				OwnerId:      testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.OwnerId,
				RepositoryId: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.RepositoryId,
			},
			err: "twirp error invalid_argument: subject_digest,subject_digests either argument must be provided",
		},
		{
			name: "Both subject_digest and subject_digests args provided",
			request: &rpc.ListAttestationsBySubjectDigestRequest{
				OwnerId:       testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.OwnerId,
				RepositoryId:  testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.RepositoryId,
				SubjectDigest: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.SubjectDigest,
				SubjectDigests: []string{
					testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.SubjectDigest,
					testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.SubjectDigest,
				},
			},
			err: "twirp error invalid_argument: subject_digest,subject_digests only one argument may be provided",
		},
		{
			name: "Too many digests provided in subject_digests",
			request: &rpc.ListAttestationsBySubjectDigestRequest{
				OwnerId:      testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.OwnerId,
				RepositoryId: testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.RepositoryId,
				SubjectDigests: func() []string {
					subjectDigests := make([]string, 0, attestation.SubjectLimit+1)
					for i := 0; i < attestation.SubjectLimit+1; i++ {
						subjectDigests = append(subjectDigests, testFixture.getPkgBySubjectDigestReqWithOwnerRepoID.SubjectDigest)
					}
					return subjectDigests
				}(),
			},
			err: "twirp error invalid_argument: subject_digests too many digests provided",
		},
	}

	for _, tc := range testcases {
		server, _, cleanUp := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// Create the attestation multiple times
		for i := 0; i < 5; i++ {
			_, err := twClient.CreateAttestationByOwnerRepository(ctx, testFixture.createArtifactAttReq)
			assert.NoError(t, err, tc.name)
		}

		ctx = createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)
		resp, err := twClient.ListAttestationsBySubjectDigest(ctx, tc.request)

		if err != nil {
			assert.ErrorContains(t, err, tc.err, tc.name)
			assert.Nil(t, resp, tc.name)
		} else {
			assert.NoError(t, err, tc.name)
			assert.NotNil(t, resp, tc.name)
		}

		cleanUp(t)
	}
}

/*
  GitHubAPI - GetAttestationSummaryByRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/GetAttestationSummaryByRepository
*/

type getAttestationSummaryByRepositoryTestCase struct {
	name           string
	createAttReq   *rpc.CreateAttestationByOwnerRepositoryRequest
	showAttByIdReq *rpc.GetAttestationSummaryByRepositoryRequest
	expectedErr    string
}

// GitHubAPI: GetAttestationSummaryByRepository
func TestGitHubAPIGetAttestationSummaryByRepository(t *testing.T) {
	testFixture := newFixtureReadGitHubAPI(t)
	testcases := []getAttestationSummaryByRepositoryTestCase{
		{
			name:           "GetAttestationSummaryByRepository with valid id",
			createAttReq:   testFixture.createPkgAttReqSigstore300WithOwnerRepoID,
			showAttByIdReq: testFixture.showAttByIdReq,
			expectedErr:    "",
		},
		{
			name:           "GetAttestationSummaryByRepository with invalid id",
			createAttReq:   testFixture.createArtifactAttReq,
			showAttByIdReq: testFixture.showAttByInvalidIdReq,
			expectedErr:    "twirp error not_found: no matching attestations found",
		},
	}

	for _, tc := range testcases {
		server, _, cleanUp := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// Create the attestation
		_, err := twClient.CreateAttestationByOwnerRepository(ctx, tc.createAttReq)
		assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))

		ctx = createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		showAttByIdReq := tc.showAttByIdReq
		perPage := uint32(1)
		listAttByRepoReq := &rpc.ListAttestationsByRepositoryRequest{
			OwnerId:      *showAttByIdReq.OwnerId,
			RepositoryId: *showAttByIdReq.RepositoryId,
			PerPage:      &perPage,
		}
		// Get the first attestation so we can get its ID
		listAttestationsResp, err := twClient.ListAttestationSummariesByRepository(ctx, listAttByRepoReq)
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
			assert.ErrorContains(t, err, tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, showAttestationResponse, fmt.Sprintf("test '%s': should have nil response", tc.name))
		} else {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
			attestation := listAttestationsResp.AttestationSummaries[0]
			showAtt := showAttestationResponse
			expectedSubjects := []rpc.Subject{
				{
					SubjectName:   "pkg:npm/sigstore@2.2.0",
					SubjectDigest: "sha512:7dc53d7251f012cb36fccff5d4514cf09c1ce0f8c181b857a0db24a0ae60ba82b4a8640149e51b419449f81d9f0c522f8727f482a09a3eb7a5f66b336e1031ba",
				},
			}

			// AttestationSummary which is primarily built from an AttestationRecord
			// these are used on the Attestation Show UI in dotcom (https://github.com/<ORG>/<REPO>/attestations/<ATTESTATION-ID>)
			assert.Equal(t, showAtt.AttestationSummary.Id, attestation.Id, fmt.Sprintf("test '%s': should have expected id", tc.name))
			assert.Equal(t, showAtt.AttestationSummary.OwnerId, attestation.OwnerId, fmt.Sprintf("test '%s': should have expected owner_id", tc.name))
			assert.Equal(t, showAtt.AttestationSummary.RepositoryId, attestation.RepositoryId, fmt.Sprintf("test '%s': should have expected repository_id", tc.name))
			assert.Equal(t, showAtt.AttestationSummary.CreatedAt, attestation.CreatedAt, fmt.Sprintf("test '%s': should have expected created_at", tc.name))
			assert.Equal(t, showAtt.AttestationSummary.PredicateType, attestation.PredicateType, fmt.Sprintf("test '%s': should have expected predicate_type", tc.name))
			assert.NotNil(t, attestation.CertificateSummary, fmt.Sprintf("test '%s': should have a certificate summary", tc.name))
			assert.NotEmpty(t, showAtt.AttestationSummary.Subjects, fmt.Sprintf("test '%s': should have expected subjects", tc.name))
			assert.Equal(t, expectedSubjects[0].SubjectName, showAttestationResponse.AttestationSummary.Subjects[0].SubjectName, fmt.Sprintf("test '%s': should have expected subject name", tc.name))
			assert.Equal(t, expectedSubjects[0].SubjectDigest, showAttestationResponse.AttestationSummary.Subjects[0].SubjectDigest, fmt.Sprintf("test '%s': should have expected subject digest", tc.name))
		}

		cleanUp(t)
	}
}

/*
  GitHubAPI - GetAttestationByRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/GetAttestationByRepository
*/

type getAttestationByRepositoryTestCase struct {
	name          string
	getAttByIdReq *rpc.GetAttestationByRepositoryRequest
	expectedErr   string
}

// GitHubAPI: GetAttestationByRepository
func TestGitHubAPIGetAttestationByRepository(t *testing.T) {
	testFixture := newFixtureReadGitHubAPI(t)
	testcases := []getAttestationByRepositoryTestCase{
		{
			name:          "GetAttestationByRepository with valid id",
			getAttByIdReq: testFixture.getAttByIdReq,
			expectedErr:   "",
		},
		{
			name:          "GetAttestationByRepository with invalid id",
			getAttByIdReq: testFixture.getAttByInvalidIdReq,
			expectedErr:   "twirp error not_found: no attestation for given (purl, predicateType) exists",
		},
	}

	for _, tc := range testcases {
		server, _, cleanUp := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)

		ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// Create the attestation
		_, err := twClient.CreateAttestationByOwnerRepository(ctx, testFixture.createArtifactAttReq)
		assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		ctx = createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		getAttByIdReq := tc.getAttByIdReq
		perPage := uint32(1)
		listAttByRepoReq := &rpc.ListAttestationsByRepositoryRequest{
			OwnerId:      *getAttByIdReq.OwnerId,
			RepositoryId: *getAttByIdReq.RepositoryId,
			PerPage:      &perPage,
		}
		// Get the first attestation so we can get its ID
		attestationsResp, err := twClient.ListAttestationSummariesByRepository(ctx, listAttByRepoReq)
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
			assert.ErrorContains(t, err, tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
			assert.Nil(t, resp, fmt.Sprintf("test '%s': should have nil response", tc.name))
		} else {
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error: %v", tc.name, err))
			fmt.Println(resp.Attestation)
			assert.Equal(t, resp.Attestation.PredicateType, "https://slsa.dev/provenance/v1", fmt.Sprintf("test '%s': should have expected predicate type", tc.name))
			assert.Equal(t, resp.Attestation.Id, attestationsResp.AttestationSummaries[0].Id, fmt.Sprintf("test '%s': should have expected id", tc.name))
			assert.NotZero(t, resp.Attestation.SignedAccessSignatureUrl, fmt.Sprintf("test '%s': should return a valid SAS URL", tc.name))
		}

		cleanUp(t)
	}
}

/*
  GitHubAPI - ListAttestationSummariesByRepository
	  POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationSummariesByRepository
*/

// GitHubAPI: ListAttestationsByRepositorySummary
func TestGitHubAPIListAttestationSummariesByRepository(t *testing.T) {
	testFixture := newFixtureReadGitHubAPI(t)
	// for now, we're using the same bundle for each attestation fixture
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

	for _, tc := range listAttestationsWithPageInfoTestcases {
		server, _, cleanUp := newServerWithDB(t)

		// Create the attestation
		dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
		twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
		ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// Create the attestation multiple times
		for i := 0; i < tc.numOfAttestations; i++ {
			_, err := twClient.CreateAttestationByOwnerRepository(ctx, testFixture.createPkgAttReqSigstore300WithOwnerRepoID)
			assert.NoError(t, err, fmt.Sprintf("test '%s': should not error", tc.name))
		}

		ctx = createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

		// If a cursor is provided, we need to update the request to include the cursor
		listAttByRepoReq := testFixture.listAttByRepoReq
		if tc.cursor != nil {
			perPage := uint32(tc.cursor.PerPage)
			listAttByRepoReq = &rpc.ListAttestationsByRepositoryRequest{
				OwnerId:      testFixture.listAttByRepoReq.OwnerId,
				RepositoryId: testFixture.listAttByRepoReq.RepositoryId,
				PerPage:      &perPage,
				Before:       &tc.cursor.Before,
				After:        &tc.cursor.After,
			}
		}
		resp, err := twClient.ListAttestationSummariesByRepository(ctx, listAttByRepoReq)

		if tc.expectedErr != "" {
			assert.ErrorContains(t, err, tc.expectedErr, fmt.Sprintf("test '%s': should error", tc.name))
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

		cleanUp(t)
	}
}

// GitHubAPI: ListAttestationSummariesByRepository
func TestGitHubAPIListAttestationSummariesByRepository_PredicateTypeFiltering(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

	// Create attestations with GitHub bundles
	bundles := []*v1.Bundle{data.SigstoreBundleAttestDemoProvenance(t), data.SigstoreBundleAttestDemoSBOM(t)}
	ownerID, repoID := uint64(42), uint64(12345)
	for _, bundle := range bundles {
		createReq := &rpc.CreateAttestationByOwnerRepositoryRequest{
			Bundle:       bundle,
			OwnerId:      ownerID,
			RepositoryId: repoID,
		}
		_, err := twClient.CreateAttestationByOwnerRepository(ctx, createReq)
		assert.NoError(t, err)
	}

	for _, tc := range predicateFilterTestCases {
		perPage := uint32(30)
		getReq := &rpc.ListAttestationsByRepositoryRequest{
			OwnerId:       ownerID,
			PerPage:       &perPage,
			PredicateType: &tc.predicateType,
			RepositoryId:  repoID,
		}

		resp, err := twClient.ListAttestationSummariesByRepository(ctx, getReq)
		if tc.errMessage != "" {
			assert.ErrorContains(t, err, tc.errMessage, tc.name)
			assert.Nil(t, resp, tc.name)
		} else {
			assert.NoError(t, err, tc.name)
			assert.Len(t, resp.AttestationSummaries, tc.expectedAttestationCount, tc.name)
		}
	}
}

// GitHubAPI: ListAttestationSummariesByRepository
func TestGitHubAPIListAttestationSummariesByRepository_CreationDateFiltering(t *testing.T) {
	server, store, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	// Create attestations with GitHub bundles
	var twenty25 = time.Date(2025, 2, 11, 10, 33, 55, 0, time.UTC)
	var twenty24 = time.Date(2024, 2, 11, 2, 34, 0, 0, time.UTC)
	var twenty21 = time.Date(2021, 2, 11, 17, 45, 0, 0, time.UTC)
	creationDates := []time.Time{twenty21, twenty24, twenty25}
	ownerID, repoID := uint64(42), uint64(12345)
	sgb, err := sgbundle.NewBundle(data.SigstoreBundleAttestDemoProvenance(t))
	assert.NoError(t, err)
	vc, err := sgb.VerificationContent()
	assert.NoError(t, err)

	for _, date := range creationDates {
		record := &attestation.Record{
			Certificate:  vc.Certificate(),
			CreatedAt:    date,
			DomainID:     2,
			OwnerID:      &ownerID,
			RepositoryID: &repoID,
			Subjects: []attestation.Subject{
				{
					Name:          "foo/bar",
					SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "abc123"},
				},
			},
		}

		err := store.StoreGitHubAttestation(context.Background(), record, sgb)
		assert.NoError(t, err)
	}

	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

	// confirm all records are returned when no created filter is provided
	perPage := uint32(30)
	getReq := &rpc.ListAttestationsByRepositoryRequest{
		OwnerId:      ownerID,
		PerPage:      &perPage,
		RepositoryId: repoID,
	}
	resp, err := twClient.ListAttestationSummariesByRepository(ctx, getReq)
	assert.NoError(t, err)
	assert.Len(t, resp.AttestationSummaries, 3)

	// confirm one specific record is returned when created after filter is provided
	createdAfter := ">2024-02-11"
	getReq.Created = &createdAfter
	resp, err = twClient.ListAttestationSummariesByRepository(ctx, getReq)
	assert.NoError(t, err)
	assert.Len(t, resp.AttestationSummaries, 1)
	createdTimestamp := resp.AttestationSummaries[0].GetCreatedAt().AsTime()
	assert.True(t, createdTimestamp.Equal(twenty25))

	// confirm one specific record is returned when created before filter is provided
	createdBefore := "<2024-02-11"
	getReq.Created = &createdBefore
	resp, err = twClient.ListAttestationSummariesByRepository(ctx, getReq)
	assert.NoError(t, err)
	assert.Len(t, resp.AttestationSummaries, 1)
	createdTimestamp = resp.AttestationSummaries[0].GetCreatedAt().AsTime()
	assert.True(t, createdTimestamp.Equal(twenty21))

	// confirm one specific record is returned when created on filter is provided
	createdOn := "=2024-02-11"
	getReq.Created = &createdOn
	resp, err = twClient.ListAttestationSummariesByRepository(ctx, getReq)
	assert.NoError(t, err)
	assert.Len(t, resp.AttestationSummaries, 1)
	createdTimestamp = resp.AttestationSummaries[0].GetCreatedAt().AsTime()
	assert.True(t, createdTimestamp.Equal(twenty24))
}

// GitHubAPI: ListAttestationSummariesByRepository
func TestGitHubAPIListAttestationSummariesByRepository_SubjectNameFiltering(t *testing.T) {
	server, _, cleanUp := newServerWithDB(t)
	defer cleanUp(t)

	ownerID, repoID := uint64(42), uint64(12345)
	dotcomClient, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewGitHubAPIJSONClient(server.URL, dotcomClient)
	ctx := createCtxWithHMACClientIDHeader(t, dotcomAuthConfig.ClientID)

	createReq := &rpc.CreateAttestationByOwnerRepositoryRequest{
		Bundle:       data.SigstoreBundleAttestDemoProvenance(t),
		OwnerId:      ownerID,
		RepositoryId: repoID,
	}
	createResp, err := twClient.CreateAttestationByOwnerRepository(ctx, createReq)
	assert.NoError(t, err)
	assert.NotNil(t, createResp)

	// confirm all records are returned when no created filter is provided
	perPage := uint32(30)
	getReq := &rpc.ListAttestationsByRepositoryRequest{
		OwnerId:      ownerID,
		PerPage:      &perPage,
		RepositoryId: repoID,
	}
	getResp, err := twClient.ListAttestationSummariesByRepository(ctx, getReq)
	assert.NoError(t, err)
	assert.Len(t, getResp.AttestationSummaries, 1)

	// Successfully fetch attestation with subject name matching
	subjectName := "demo"
	getReq.SubjectName = &subjectName
	getResp, err = twClient.ListAttestationSummariesByRepository(ctx, getReq)
	assert.NoError(t, err)
	assert.Len(t, getResp.AttestationSummaries, 1)

	// Fail to fetch attestation with no matching subject name pattern
	subjectName = "no-matching-subject"
	getReq.SubjectName = &subjectName
	getResp, err = twClient.ListAttestationSummariesByRepository(ctx, getReq)
	assert.Equal(t, err, ErrNoMatchingAttestations)
	assert.Nil(t, getResp)
}
