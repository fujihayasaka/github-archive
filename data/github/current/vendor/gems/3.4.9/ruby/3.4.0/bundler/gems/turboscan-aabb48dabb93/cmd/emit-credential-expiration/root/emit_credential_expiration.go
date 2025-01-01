// Package root represents a command that emits metrics about the expiration of any credentials currently in use.
package root

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts/config"
	"github.com/spf13/cobra"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
)

const apiRoot = "https://graph.microsoft.com/v1.0"
const defaultScope = "https://graph.microsoft.com/.default"

var EmitCredentialExpirationCmd = &cobra.Command{
	Use:   "emit-credential-expiration",
	Short: "Emits a metrics about the expiration of any credentials currently in use.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cronjob.Execute("emit-credential-expiration", func(ctx context.Context, cfg *config.Config) error {
			return realMain(ctx, cmd, cfg)
		})
	},
}

func emitMetric(ctx context.Context, credential string, remaining time.Duration) {
	stats := appctx.Stats(ctx).WithTags(map[string]string{
		"credential": credential,
	})
	hoursRemaining := int64(remaining.Hours())
	appctx.Logger(ctx).Info("Recording credential expiration.", kvp.String("gh.turboscan.credential.name", credential), kvp.Int64("gh.turboscan.credential.hours_to_expiry", hoursRemaining))
	stats.Gauge("credential_expiration", nil, hoursRemaining)
}

type azureApplicationResponse struct {
	Value []azureApplication `json:"value"`
}

type azurePasswordCredential struct {
	EndDateTime time.Time `json:"endDateTime"`
	Hint        string    `json:"hint"`
}

type azureApplication struct {
	PasswordCredentials []azurePasswordCredential `json:"passwordCredentials"`
}

func emitAzureSPNExpiration(ctx context.Context, cfg *config.Config) error {
	appctx.Logger(ctx).Info("Checking Azure SPN expiration...")
	if cfg.AzureClientSecret == "" {
		appctx.Logger(ctx).Info("No Azure client secret provided, skipping Azure SPN expiration check.")
		return nil
	}

	credential, err := azidentity.NewClientSecretCredential(cfg.AzureTenantID, cfg.AzureClientID, cfg.AzureClientSecret, nil)
	if err != nil {
		return errors.Wrap(err, "failed to create service principal credential")
	}

	tokenResponse, err := credential.GetToken(ctx, policy.TokenRequestOptions{Scopes: []string{defaultScope}})
	if err != nil {
		return errors.Wrap(err, "failed to get token")
	}

	client := http.DefaultClient

	listRequest, err := http.NewRequestWithContext(ctx, "GET", apiRoot+"/applications", nil)
	if err != nil {
		return errors.Wrap(err, "failed to create request")
	}
	listRequest.Header.Set("Authorization", "Bearer "+tokenResponse.Token)
	filter := fmt.Sprintf("appId eq '%s'", cfg.AzureClientID)
	listRequest.URL.RawQuery = url.Values{
		"$filter": []string{filter},
	}.Encode()

	listResponse, err := client.Do(listRequest)
	if err != nil {
		return errors.Wrap(err, "failed to list applications")
	}
	if listResponse.StatusCode != http.StatusOK {
		return errors.New("failed to list applications with status " + listResponse.Status)
	}

	applications := azureApplicationResponse{}
	defer listResponse.Body.Close()
	if err := json.NewDecoder(listResponse.Body).Decode(&applications); err != nil {
		return errors.Wrap(err, "failed to decode applications")
	}
	if len(applications.Value) == 0 {
		return errors.New("failed to find application")
	}

	application := applications.Value[0]

	var expiration *time.Time
	credentials := application.PasswordCredentials
	for _, credential := range credentials {
		if strings.HasPrefix(cfg.AzureClientSecret, credential.Hint) {
			expiration = &credential.EndDateTime
			break
		}
	}

	if expiration == nil {
		return errors.New("failed to find expiration date for current SPN")
	}

	emitMetric(ctx, "azure", time.Until(*expiration))

	return nil
}

func realMain(ctx context.Context, _ *cobra.Command, cfg *config.Config) error {
	appctx.Logger(ctx).Info("emit-credential-expiration started.")

	err := emitAzureSPNExpiration(ctx, cfg)
	if err != nil {
		return err
	}

	appctx.Logger(ctx).Info("emit-credential-expiration finished.")
	return nil
}
