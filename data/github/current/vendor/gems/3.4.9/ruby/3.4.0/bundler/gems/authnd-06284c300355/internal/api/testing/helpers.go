package testing

import (
	"context"
	"crypto/ecdsa"
	"net/http"
	"net/http/httptest"
	"testing"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/authenticator"
	apiConfig "github.com/github/authnd/internal/api/config"
	"github.com/github/authnd/internal/api/credentials"
	"github.com/github/authnd/internal/api/devices"
	"github.com/github/authnd/internal/api/exchanger"
	"github.com/github/authnd/internal/api/middleware"
	"github.com/github/authnd/internal/api/mux"
	"github.com/github/authnd/internal/api/tenancy"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/config"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/publisher"
	"github.com/github/authnd/internal/common/store"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/github/authnd/internal/tester"
	"github.com/github/go-stats"
	twauth "github.com/github/go-twirp/v2/client/auth"
	pbhydro "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/golang/protobuf/proto" //nolint - can't unmarshal envelope with "google.golang.org/protobuf/proto"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"
)

var (
	TestHMACKey            = "octocat"
	TestCatalogServiceName = "test_cat_service_name"

	tokenExchangerPrivateKey = crypto.MustCreateECDSAPrivateKey()
)

func GetEnvelope(t *testing.T, bytes []byte) *pbhydro.Envelope {
	t.Helper()

	envelope := &pbhydro.Envelope{}
	err := proto.Unmarshal(bytes, envelope)
	if err != nil {
		panic(err)
	}
	return envelope
}

// testAuthenticator sets up a test server and returns the client to make calls
// against the server.
func TestAuthenticator(t *testing.T, store store.Store, isEnterpriseServer bool) pb.Authenticator {
	t.Helper()

	ts := CreateTestAuthenticationServer(t, store, isEnterpriseServer)
	client, err := twauth.NewRequestHMACSigner(TestHMACKey, ts.Client())
	require.NoError(t, err)

	return pb.NewAuthenticatorJSONClient(ts.URL, client)
}

func CreateTestAuthenticationServer(t *testing.T, store store.Store, isEnterpriseServer bool) *httptest.Server {
	t.Helper()

	hooks := middleware.NewServerHooks(TestApiConfig(), testhelpers.GetTestLogger(), stats.NullStatter, TestHMACKey)
	server := authenticator.NewAuthenticatorServer(
		store,
		hooks,
		isEnterpriseServer,
	)

	return createTestServer(t, server, store)
}

func CreateTestTokenExchangerServer(t *testing.T, store store.Store, isEnterpriseServer bool) (*httptest.Server, *ecdsa.PublicKey) {
	t.Helper()

	hooks := middleware.NewServerHooks(TestApiConfig(), testhelpers.GetTestLogger(), stats.NullStatter, TestHMACKey)
	server, err := exchanger.NewTokenExchangerServer(
		store,
		hooks,
		tokenExchangerPrivateKey,
		isEnterpriseServer,
	)
	require.NoError(t, err)

	return createTestServer(t, server, store), &tokenExchangerPrivateKey.PublicKey
}

func CreateTestCredentialManagerServer(t *testing.T, store store.Store, messageChan chan hydro.Message) *httptest.Server {
	t.Helper()

	hooks := middleware.NewServerHooks(TestApiConfig(), testhelpers.GetTestLogger(), stats.NullStatter, TestHMACKey)
	server := credentials.NewCredentialManagerServer(
		store,
		createIntegrationTestEventPublisher(t, messageChan),
		hooks,
	)
	return createTestServer(t, server, store)
}

// creates an in-memory hydro source for integration testing
func createIntegrationTestEventPublisher(t *testing.T, messages chan hydro.Message) publisher.PratEventPublisher {
	cfg, err := tester.NewConfigFromEnvironment()
	require.NoError(t, err)

	if messages == nil {
		messages = make(chan hydro.Message, 10)
	}
	memorySink, err := hydro.NewMemorySink(messages)
	require.NoError(t, err)

	publisher, err := publisher.NewPratEventPublisher(
		context.Background(),
		&cfg.CommonConfig,
		func(kafka hydro.KafkaConfig) (hydro.Sink, error) { return memorySink, nil },
	)
	require.NoError(t, err)
	return publisher
}

func CreateTestMobileDeviceManagerServer(t *testing.T, store store.Store, messageChan chan hydro.Message) *httptest.Server {
	t.Helper()

	hooks := middleware.NewServerHooks(TestApiConfig(), testhelpers.GetTestLogger(), stats.NullStatter, TestHMACKey)
	server := devices.NewMobileDeviceManagerServer(
		store,
		createIntegrationTestNotifyPublisher(t, messageChan),
		hooks,
	)
	return createTestServer(t, server, store)
}

// creates an in-memory hydro source for integration testing
func createIntegrationTestNotifyPublisher(t *testing.T, messages chan hydro.Message) publisher.NotificationPublisher {
	cfg, err := tester.NewConfigFromEnvironment()
	require.NoError(t, err)

	if messages == nil {
		messages = make(chan hydro.Message, 10)
	}
	memorySink, err := hydro.NewMemorySink(messages)
	require.NoError(t, err)

	publisher, err := publisher.NewNotificationPublisher(
		context.Background(),
		&cfg.CommonConfig,
		func(kafka hydro.KafkaConfig) (hydro.Sink, error) { return memorySink, nil },
	)
	require.NoError(t, err)
	return publisher
}

func CreateTestMobileDeviceManagerServerWithMockedPublisher(t *testing.T, server pb.TwirpServer, dbStore store.BusinessesStore) *httptest.Server {
	t.Helper()

	return createTestServer(t, server, dbStore)
}

func createTestServer(t *testing.T, prefixHandler mux.PrefixHandler, dbStore store.BusinessesStore) *httptest.Server {
	t.Helper()
	resolver := tenancy.NewResolver(dbStore.FindBusinessBySlug)
	handler := mux.NewMux(testhelpers.GetTestLogger(), stats.NullStatter, commonTesting.IsProximaMode(), resolver, &integrationTestPrefixHandler{prefixHandler})
	ts := httptest.NewServer(handler)
	t.Cleanup(ts.Close)
	return ts
}

// used to wrap the prefix handler created in our integration test server
// in order to add a "with integration test" flag to the context in the request
type integrationTestPrefixHandler struct {
	prefixHandler mux.PrefixHandler
}

func (p *integrationTestPrefixHandler) PathPrefix() string {
	return p.prefixHandler.PathPrefix()
}

func (p *integrationTestPrefixHandler) ServeHTTP(writer http.ResponseWriter, req *http.Request) {
	p.prefixHandler.ServeHTTP(writer, req.WithContext(diagnostics.WithIntegrationTestFlag(req.Context())))
}

func insertMobileAuthRequests(t *testing.T, testdb *sqlx.DB, mobileAuthRequests []*models.MobileAuthRequest) {
	insert := func(query string, values ...interface{}) int64 {
		t.Helper()
		result, err := testdb.Exec(query, values...)
		require.NoError(t, err)
		id, err := result.LastInsertId()
		require.NoError(t, err)
		return id
	}

	InsertMobileAuthRequestsFunc := func(request *models.MobileAuthRequest) {
		id := insert(`
		INSERT INTO mobile_auth_requests (
			user_id,
			payload,
			challenge_number,
			created_at_utc,
			expires_at_utc,
			approved_at_utc,
			rejected_at_utc,
			type
		)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?)`,
			request.UserId,
			request.Payload,
			request.ChallengeNumber,
			request.CreatedAt,
			request.ExpiresAt,
			request.ApprovedAt,
			request.RejectedAt,
			request.Type,
		)
		request.ID = uint64(id)
	}
	for _, request := range mobileAuthRequests {
		InsertMobileAuthRequestsFunc(request)
	}
}

func SeedMobileAuthRequests(t *testing.T, mobileAuthRequests []*models.MobileAuthRequest) {
	authndDB, _, _, _ := commonTesting.OpenTestDBs(t)
	t.Cleanup(func() {
		// ensure we close db connections after each test
		authndDB.Close()
	})
	insertMobileAuthRequests(t, authndDB, mobileAuthRequests)
}

func TestApiConfig() *apiConfig.Config {
	return &apiConfig.Config{
		CommonConfig: config.CommonConfig{
			IsProxima: commonTesting.IsProximaMode(),
		},
	}
}
