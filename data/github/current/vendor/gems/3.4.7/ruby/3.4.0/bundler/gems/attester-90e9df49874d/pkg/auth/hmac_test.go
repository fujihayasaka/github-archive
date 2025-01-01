package auth

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/assert"
)

func TestNewAuthenticationMiddleware_Success(t *testing.T) {
	cfg := HMACKeys{"test"}
	mw, err := NewAuthenticationMiddleware(log.NewNullLogger(), cfg)
	assert.Nil(t, err)
	assert.NotNil(t, mw)
}
