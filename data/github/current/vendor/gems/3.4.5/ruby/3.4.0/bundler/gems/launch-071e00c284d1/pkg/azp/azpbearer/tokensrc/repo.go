package tokensrc

import (
	"fmt"

	"github.com/github/launch/keystore"
	"github.com/github/launch/pkg/azp/azpbearer"
	"github.com/github/launch/pkg/azp/azpbearer/jwt"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/azp/config"
)

const repoClientTokenURLTemplate = "%s/_apis/oauth2/token/%s"

type RepoClientTokenSourceFactory struct {
	baseURL string
	jp      *jwt.ProviderForRepoClient
	btc     *azpbearer.Client
}

func NewRepoClientTokenSourceFactory(cfg config.AzureProviderConfig, ks keystore.Store, btc *azpbearer.Client, environment string) *RepoClientTokenSourceFactory {
	jp := jwt.NewProviderForRepoClient(ks, environment)
	return &RepoClientTokenSourceFactory{
		baseURL: cfg.TokenServiceBaseURL,
		jp:      jp,
		btc:     btc,
	}
}

func (rf *RepoClientTokenSourceFactory) For(r *azptypes.BackingResources) launchhttp.TokenSource {
	reqURL := rf.getTokenURL(r.TenantID)
	j := rf.jp.NewProvider(r.TenantName, r.EncryptedPrivateKey)
	return rf.btc.TokenSourceFor(j, reqURL, r.ClientID, "")
}

func (rf *RepoClientTokenSourceFactory) getTokenURL(tenantID string) string {
	return fmt.Sprintf(repoClientTokenURLTemplate, rf.baseURL, tenantID)
}
