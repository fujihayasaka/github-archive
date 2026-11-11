package chatops

import (
	"bytes"
	"crypto/rsa"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	snapshotsMock "github.com/github/dependency-snapshots-api/internal/snapshots/mock"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/go-chatops/v2"
	"github.com/github/go-exceptions"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func signBotRequest(t *testing.T, key *rsa.PrivateKey, req *http.Request, body string) {
	t.Helper()
	sigBy, err := chatops.Sign(key, chatops.URLHeaderSignatureInput(req.URL, req.Header, body))
	require.NoError(t, err)
	sig := &chatops.Signature{KeyID: "test", Signature: sigBy}
	req.Header.Set("Chatops-Signature", sig.HeaderValue())
}

func pubBytes(t *testing.T) []byte {
	t.Helper()
	pubBy, err := os.ReadFile("testdata/key.pub.pem")
	require.NoError(t, err)
	return pubBy
}

func botKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	privBy, err := os.ReadFile("testdata/key.pem")
	require.NoError(t, err)
	privkey, err := chatops.ReadPEMPrivateKey(privBy)
	require.NoError(t, err)
	return privkey
}

func sendCmd(t *testing.T, rawurl string, creq *chatops.CommandRequest) *chatops.CommandResponse {
	t.Helper()
	by, err := json.Marshal(creq)
	require.NoError(t, err)
	req, err := http.NewRequest("POST", rawurl, bytes.NewReader(by))
	require.NoError(t, err)
	signBotRequest(t, botKey(t), req, string(by))
	res, err := http.DefaultClient.Do(req)
	require.NoError(t, err)
	cres := &chatops.CommandResponse{}
	err = json.NewDecoder(res.Body).Decode(cres)
	require.NoError(t, err)
	require.NoError(t, res.Body.Close())
	return cres
}

func TestDisabledChatops(t *testing.T) {
	isDisabledChatop(t, "get-included-snapshots")
	isDisabledChatop(t, "exclude-snapshot")
	isDisabledChatop(t, "hmac")
}

func TestTotalSnapshots(t *testing.T) {
	mockedSnapshotsService, srvURL := prepTest(t)

	expectedCounts := &interfaces.ActivityCounts{Total: 100, InLastDay: 10, InLastWeek: 50}
	mockedSnapshotsService.On("TotalSnapshotCounts", mock.Anything).Return(expectedCounts, nil)

	res := sendCmd(t, srvURL+"/_chatops", &chatops.CommandRequest{
		Method: "total-snapshots",
		User:   "bob",
		RoomID: "test",
	})

	assert.Contains(t, res.Result, fmt.Sprintf("Counted %v snapshots total, %v in the last day and %v in the last week", expectedCounts.Total, expectedCounts.InLastDay, expectedCounts.InLastWeek))
}

func TestUniqueRepositories(t *testing.T) {
	mockedSnapshotsService, srvURL := prepTest(t)

	expectedCounts := &interfaces.ActivityCounts{Total: 100, InLastDay: 10, InLastWeek: 50}
	mockedSnapshotsService.On("UniqueRepositoryCounts", mock.Anything).Return(expectedCounts, nil)

	res := sendCmd(t, srvURL+"/_chatops", &chatops.CommandRequest{
		Method: "unique-repositories",
		User:   "bob",
		RoomID: "test",
	})

	assert.Contains(t, res.Result, fmt.Sprintf("Counted %v unique repositories total, %v in the last day and %v in the last week", expectedCounts.Total, expectedCounts.InLastDay, expectedCounts.InLastWeek))
}

func prepTest(t *testing.T) (mockSnapshots *snapshotsMock.MockedSnapshotsService, srvURL string) {
	t.Helper()
	mockedSnapshotsService := &snapshotsMock.MockedSnapshotsService{}

	mux := http.NewServeMux()
	srv := httptest.NewServer(mux)

	r, _ := exceptions.NewReporter()
	cfg := &config.Config{ChatopsBaseURL: srv.URL + "/", ChatopsBotPublicKey: string(pubBytes(t))}
	chatopsHandler, err := NewChatopsHandler(cfg, r, mockedSnapshotsService)
	require.NoError(t, err)
	chatopsHandler.Setup(mux)

	return mockedSnapshotsService, srv.URL
}

func isDisabledChatop(t *testing.T, method string) {
	t.Helper()
	_, srvURL := prepTest(t)

	res := sendCmd(t, srvURL+"/_chatops", &chatops.CommandRequest{
		Method: method,
		User:   "bob",
		RoomID: "test",
		Params: map[string]string{},
	})

	assert.Containsf(t, res.Result, "This chatop is disabled.", "Expected the '%s' chatop to be disabled", method)
}
