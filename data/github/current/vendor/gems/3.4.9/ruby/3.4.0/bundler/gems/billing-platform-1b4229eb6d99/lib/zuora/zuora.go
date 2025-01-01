package zuora

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/log"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/clientcredentials"
)

type Client struct {
	UsageService UsageServiceInterface
}

func NewClient(zuoraApiUrl string, zuoraClientID string, zuoraClientSecret string, logger log.Logger) *Client {
	oauthConf := &clientcredentials.Config{
		ClientID:     zuoraClientID,
		ClientSecret: zuoraClientSecret,
		TokenURL:     zuoraApiUrl + "/oauth/token",
		AuthStyle:    oauth2.AuthStyleInParams,
	}
	httpClientWithToken := oauthConf.Client(context.Background())
	httpClientWithToken.Timeout = 60 * time.Second

	return &Client{
		UsageService: newUsageService(*httpClientWithToken, zuoraApiUrl, logger),
	}
}
