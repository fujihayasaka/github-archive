//go:build integration

package transport

import (
	"context"
	"database/sql"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	twcauth "github.com/github/go-twirp/v2/client/auth"
	"github.com/github/trust-metadata-api/pkg/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

const (
	TestDBURI                                                = "tma:TMAdevP4ssw0rd!@tcp(127.0.0.1:3337)/tma_dev?parseTime=true"
	SubjectDigest                                            = "sha512:bbfd372fc9beeb777fe35d05bb10c0c70a9733d366a75fed7dd18866c7391de3ee7e88ba74dd47abf3e15c845e547fcf0e5c3da80854c751554224d3a6d4e55f"
	TestPurl                                                 = "pkg:npm/some/package@1.2.3"
	BadPurl                                                  = "pknpm/foo/bar@1.2.3"
	SubjectDigestOfSigstoreBundleFromGenerateBuildProvenance = "sha256:9e247b886e8b2f2d4de285cd4a178b954e99a8c6173b43d63a2af4f180f4b1a0"
)

// GitHubAPI (GitHub Domain)
var dotcomAuthConfig = auth.ClientConfig{
	ClientID: "dotcom",
	Domain:   "github",
	Keys:     []string{"ffsddfsf"},
}

// PackageInfoReadAPI (NPM Domain)
var npmReadAuthConfig = auth.ClientConfig{
	ClientID: "npm/read",
	Domain:   "npm",
	Keys:     []string{"decafbad"},
}

// PackageInfoWriteAPI (NPM Domain)
var npmWriteAuthConfig = auth.ClientConfig{
	ClientID: "uploading-worker",
	Domain:   "npm",
	Keys:     []string{"feedbeef"},
}

// Test HMAC Configs
var testHMACConfig = ServerAuthConfig{
	LegacyTMA: []auth.ClientConfig{npmWriteAuthConfig},
	PkgRead:   []auth.ClientConfig{npmReadAuthConfig},
	PkgWrite:  []auth.ClientConfig{npmWriteAuthConfig},
	Dotcom:    []auth.ClientConfig{dotcomAuthConfig},
}

// cleanUp truncates the attestations table and shuts down the server and database connections
func cleanUp(t *testing.T, server *httptest.Server, db *sql.DB, azClient azureblob.Client) {
	// clean up the attestations container
	if err := azClient.DeleteContainer(context.Background(), "attestations"); err != nil {
		t.Fatal("failed to delete attestations container in Azure blob storage", err)
	}

	// clean up the attestation table
	_, err := db.Exec("TRUNCATE attestations")
	if err != nil {
		t.Fatal("failed to truncate attestations table", err)
	}

	// clean up the attestations_subjects table
	_, err = db.Exec("TRUNCATE attestations_subjects")
	if err != nil {
		t.Fatal("failed to truncate attestations_subjects table", err)
	}

	// shut everything down
	db.Close()
	server.Close()
}

// newServerWithTransactionDB creates a new HTTP server with a new database
func newServerWithDB(t *testing.T, opts ...HTTPServerOption) (*httptest.Server, *sql.DB, azureblob.Client) {
	db, err := sql.Open("mysql", TestDBURI)
	require.NoError(t, err)

	azClient, err := azureblob.NewLocalClient("attestations")
	require.NoError(t, err)

	err = azClient.CreateContainer(context.Background(), "attestations")
	require.NoError(t, err)

	dbEndpoints := storage.DatabaseEndpoints{
		Primary: mysql.NewLiveDatabaseFromConn(db, log.NewNullLogger(), stats.NullStatter),
	}
	dbEndpoints.Replica = dbEndpoints.Primary

	store := storage.NewLiveStore(azClient, &dbEndpoints)
	tma := service.NewTestTMAWithStore(t, store)

	// setup a new HTTP server with default options unless overridden
	var httpServer *HTTPServer
	if len(opts) == 0 {
		httpServer, err = NewHTTP(tma, "8888", WithHMACConfig(testHMACConfig))
		require.NoError(t, err)
	} else {
		httpServer, err = NewHTTP(tma, "8888", opts...)
		require.NoError(t, err)
	}

	return httptest.NewServer(httpServer), db, azClient
}

// createCtxWithHMACClientIDHeader creates a context object with the
// HMAC Client ID request header that can be passed to a Twirp client for authenticated requests
func createCtxWithHMACClientIDHeader(t *testing.T, clientID string) context.Context {
	headers := map[string]string{
		auth.HMACClientHeader: clientID,
	}
	return createCtxWithHeaders(t, headers)
}

// createCtxWithTenantIDAndHMACClientIDHeader creates a context object with the
// HMAC Client ID and Tenant ID request headers that can be passed to a Twirp client for authenticated requests
func createCtxWithTenantIDAndHMACClientIDHeader(t *testing.T, clientID, tenantID string) context.Context {
	headers := map[string]string{
		auth.HMACClientHeader: clientID,
		service.TenantID:      tenantID,
	}
	return createCtxWithHeaders(t, headers)
}

func createCtxWithHeaders(t *testing.T, headers map[string]string) context.Context {
	if headers == nil {
		return context.Background()
	}

	header := make(http.Header)
	for k, v := range headers {
		header.Set(k, v)
	}

	ctx, err := twirp.WithHTTPRequestHeaders(context.Background(), header)
	require.NoError(t, err, "failed to create context with Twirp request headers")

	return ctx
}

func createCtxWithTestClientIpAddr(ctx context.Context) context.Context {
	return context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")
}

// trying to publish an attestation to GitHub API with NPM domain should return an error
func TestArtifactInfoWriteWithNPMDomain(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)
	fixture := newFixtureGitHubAPI(t)

	// Create the attestation
	clientDotocm, _ := twcauth.NewBodyHMACSigner(testHMACConfig.Dotcom[0].Keys[0], http.DefaultClient)
	twClientDotcom := rpc.NewGitHubAPIJSONClient(server.URL, clientDotocm)

	// using npm client as the client ID
	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.PkgWrite[0].ClientID)
	_, err := twClientDotcom.CreateAttestationByOwnerRepository(ctx, fixture.createArtifactAttReq)
	var twirpErr twirp.Error
	assert.ErrorAs(t, err, &twirpErr)
	assert.Equal(t, twirp.Unauthenticated, twirpErr.Code())
}

func TestPackageLog(t *testing.T) {
	server, db, azClient := newServerWithDB(t)
	defer cleanUp(t, server, db, azClient)

	client, _ := twcauth.NewBodyHMACSigner(testHMACConfig.LegacyTMA[0].Keys[0], http.DefaultClient)
	twClient := rpc.NewTrustMetadataAPIProtobufClient(server.URL, client)

	ctx := createCtxWithHMACClientIDHeader(t, testHMACConfig.LegacyTMA[0].ClientID)

	resp, err := twClient.LogErr(ctx, &rpc.LogErrRequest{
		Message: "test",
	})
	assert.NoError(t, err)
	assert.Equal(t, resp.ErrorMessage, "test")
}
