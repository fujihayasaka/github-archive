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
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"

	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

const (
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
	PkgRead:  []auth.ClientConfig{npmReadAuthConfig},
	PkgWrite: []auth.ClientConfig{npmWriteAuthConfig},
	Dotcom:   []auth.ClientConfig{dotcomAuthConfig},
}

// newServerWithTransactionDB creates a new HTTP server with a new database
func newServerWithDB(t *testing.T, opts ...HTTPServerOption) (*httptest.Server, *storage.LiveStore, func(t *testing.T)) {
	db, err := sql.Open("mysql", mysql.TestDBURI)
	require.NoError(t, err)

	azClient, err := azureblob.NewLocalClient("attestations")
	require.NoError(t, err)

	err = azClient.CreateContainer(context.Background(), "attestations")
	require.NoError(t, err)

	dbEndpoints := storage.DatabaseEndpoints{
		Primary: mysql.NewLiveDatabaseFromConn(db, log.NewNullLogger(), stats.NullStatter),
	}
	dbEndpoints.Replica = dbEndpoints.Primary

	store := storage.NewLiveStore(azClient, &dbEndpoints, nil)
	tma := service.NewTestTMAWithStore(t, store)

	// set up a new HTTP server with default options unless overridden
	var server *httptest.Server
	if len(opts) == 0 {
		httpServer, err := NewHTTP(tma, "8888", WithHMACConfig(testHMACConfig))
		require.NoError(t, err)
		server = httptest.NewServer(httpServer)
	} else {
		httpServer, err := NewHTTP(tma, "8888", opts...)
		require.NoError(t, err)
		server = httptest.NewServer(httpServer)
	}

	cleanUp := func(t *testing.T) {
		// clean up the attestations container
		err := azClient.DeleteContainer(context.Background(), "attestations")
		require.NoError(t, err, "failed to delete attestations container in Azure blob storage")

		// clean up the attestation table
		_, err = db.Exec("TRUNCATE attestations")
		require.NoError(t, err, "failed to truncate attestations table")

		// clean up the attestations_subjects table
		_, err = db.Exec("TRUNCATE attestations_subjects")
		require.NoError(t, err, "failed to truncate attestations_subjects table")

		// clean up the releases table
		_, err = db.Exec("TRUNCATE releases")
		require.NoError(t, err, "failed to truncate releases table")

		// shut everything down
		db.Close()
		server.Close()
	}

	return server, store, cleanUp
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
		tenantIDHeader:        tenantID,
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
