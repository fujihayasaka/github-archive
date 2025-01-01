package tests

import (
	"net/http"
	"testing"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/actions-usage-metrics/tests/utils"
	"github.com/github/go-twirp/client/auth"
	"github.com/stretchr/testify/assert"
)

func GetTwirpClient(t *testing.T) proto.UsageApi {
	urlBase := "http://aum.local:32474"
	cfg := utils.GetDevConfig[config.HttpConfig]()

	signer, err := auth.NewRequestHMACSigner(cfg.HMACPrimary, http.DefaultClient)
	assert.NoError(t, err, "failed to create HMAC signer")

	return proto.NewUsageApiProtobufClient(urlBase, signer)
}
