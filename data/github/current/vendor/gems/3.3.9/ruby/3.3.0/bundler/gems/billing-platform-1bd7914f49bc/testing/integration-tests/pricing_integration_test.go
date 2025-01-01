//go:build integration
// +build integration

package integrationtests_test

import (
	"fmt"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/onsi/gomega"
)

func Test_Pricing_Get_Pricing_When_DoesNotExist(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	sku := fmt.Sprintf("%d", stubs.GetRandomId())

	skuResponse := client.GetPricing(sku)

	g.Expect(skuResponse.Pricing).To(gomega.BeNil())
}

func Test_Pricing_Create_Get_Pricing(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	sku := "test sku 1"
	product := "test product 1"
	price := 99.9
	friendlyName := "test friendly name 1"
	meterType := proto.PricingMeterType_PerHourUnitCharge
	azureMeterId := "Test_Pricing_azure_meter_id_1"
	freeForPublicRepos := true
	unitType := proto.UnitType_Minutes

	lastYear := time.Now().AddDate(-1, 0, 0).Unix()
	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	effectivePriceDates := []*proto.HistoricalPrice{
		{
			StartDate: lastYear,
			EndDate:   yesterday,
			Price:     price + 1,
		},
	}

	pricing := &proto.Pricing{
		Sku:                 sku,
		Product:             product,
		Price:               price,
		FriendlyName:        friendlyName,
		MeterType:           meterType,
		AzureMeterId:        azureMeterId,
		EffectiveDatePrices: effectivePriceDates,
		FreeForPublicRepos:  freeForPublicRepos,
		UnitType:            unitType,
	}

	_ = client.UpsertPricing(pricing)
	skuResponse := client.GetPricing(pricing.GetSku())

	g.Expect(skuResponse.Pricing).To(gomega.Not(gomega.BeNil()))
	g.Expect(skuResponse.Pricing.GetSku()).To(gomega.Equal(sku))
	g.Expect(skuResponse.Pricing.GetProduct()).To(gomega.Equal(product))
	g.Expect(skuResponse.Pricing.GetMeterType()).To(gomega.Equal(meterType))
	g.Expect(skuResponse.Pricing.GetFriendlyName()).To(gomega.Equal(friendlyName))
	g.Expect(skuResponse.Pricing.GetAzureMeterId()).To(gomega.Equal(azureMeterId))
	g.Expect(skuResponse.Pricing.GetEffectiveDatePrices()[0].StartDate).To(gomega.Equal(effectivePriceDates[0].StartDate))
	g.Expect(skuResponse.Pricing.GetEffectiveDatePrices()[0].EndDate).To(gomega.Equal(effectivePriceDates[0].EndDate))
	g.Expect(skuResponse.Pricing.GetEffectiveDatePrices()[0].Price).To(gomega.Equal(effectivePriceDates[0].Price))
	g.Expect(skuResponse.Pricing.GetFreeForPublicRepos()).To(gomega.Equal(freeForPublicRepos))
	g.Expect(skuResponse.Pricing.GetUnitType()).To(gomega.Equal(unitType))
}

func Test_Pricing_Get_All_Pricing(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	client.EnsureSpecificPricingExists(32.2, "linux_16_core", "actions", "Linux 16 core")
	client.EnsureSpecificPricingExists(32.2, "linux_32_core", "actions", "Linux 32 core")

	response := client.GetAllPricing()

	g.Expect(len(response.Pricings)).To(gomega.Equal(2))
	g.Expect(response.Pricings[0].Sku).To(gomega.Equal("linux_16_core"))
	g.Expect(response.Pricings[1].Sku).To(gomega.Equal("linux_32_core"))
}

func Test_Pricing_Get_All_Pricing_With_Hard_Coded_Skus(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	response := client.GetAllPricing()

	g.Expect(len(response.Pricings)).To(gomega.Equal(len(engines.AllProductSkuV2())))
	g.Expect(response.Pricings[0]).To(gomega.BeAssignableToTypeOf(&proto.Pricing{}))
	g.Expect(response.Pricings[0].Sku).To(gomega.Not(gomega.BeNil()))

	perProductResponse := client.GetPricingsByProduct("actions")
	g.Expect(len(perProductResponse.Pricings)).To(gomega.Equal(44))
	g.Expect(perProductResponse.Pricings[0].Product).To(gomega.Equal("actions"))
}

func Test_Pricing_Get_Pricings_By_Product(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	client.EnsureSpecificPricingExists(32.2, "linux_16_core", "actions", "Linux 16 core")
	client.EnsureSpecificPricingExists(32.2, "linux_32_core", "actions", "Linux 32 core")
	client.EnsureSpecificPricingExists(32.2, "compute", "codespaces", "Codespaces Compute")
	response := client.GetPricingsByProduct("actions")

	g.Expect(len(response.Pricings)).To(gomega.Equal(2))
	g.Expect(response.Pricings[0].Sku).To(gomega.Equal("linux_16_core"))
	g.Expect(response.Pricings[1].Sku).To(gomega.Equal("linux_32_core"))
}
