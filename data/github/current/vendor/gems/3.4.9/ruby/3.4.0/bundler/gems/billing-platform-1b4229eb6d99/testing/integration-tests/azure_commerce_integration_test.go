//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"
	"time"

	"github.com/github/billing-platform/lib/azurecommerce"
	"github.com/github/billing-platform/testing/integration"
	"github.com/onsi/gomega"
)

func Test_AzureCommerce_GetSasToken_With_Cache(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	ac := azurecommerce.NewAzureCommerceClient()

	sasToken := client.AzureCommerceGetSasToken(ac, false)
	g.Expect(sasToken).NotTo(gomega.BeEmpty())
	g.Expect(sasToken).To(gomega.ContainSubstring("&sig="))

	time.Sleep(1 * time.Second)

	// Subsequent call should return the cached value
	sasToken2 := client.AzureCommerceGetSasToken(ac, false)
	g.Expect(sasToken2).To(gomega.Equal(sasToken))
}

func Test_AzureCommerce_GetSasToken_Without_Cache(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	ac := azurecommerce.NewAzureCommerceClient()

	sasToken := client.AzureCommerceGetSasToken(ac, true)
	g.Expect(sasToken).NotTo(gomega.BeEmpty())
	g.Expect(sasToken).To(gomega.ContainSubstring("&sig="))

	time.Sleep(1 * time.Second)

	// Subsequent call should return new value
	sasToken2 := client.AzureCommerceGetSasToken(ac, true)
	g.Expect(sasToken2).NotTo(gomega.Equal(sasToken))
	g.Expect(sasToken).To(gomega.ContainSubstring("&sig="))
}
