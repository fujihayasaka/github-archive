package transport

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/trust-metadata-api/pkg/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/stretchr/testify/assert"
)

func TestStatus_Success(t *testing.T) {
	var successServer = TwirpService{
		tma: service.NewTestTMA(t),
		log: log.NewNullLogger(),
	}
	resp, err := successServer.Status(context.Background(), &rpc.StatusRequest{})

	assert.Equal(t, "OK", resp.State)
	assert.Equal(t, "TestGitCommitSHA", resp.Commit)
	assert.NoError(t, err)
}

func TestNewTwirpServerAuthenticationNoHMACKey(t *testing.T) {
	tma := service.NewTestTMA(t)

	// should return an error if a hmac key was not provided
	_, err := NewTMATwirpService(tma, []auth.ClientConfig{})
	assert.Error(t, err)
}
