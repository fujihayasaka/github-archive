//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/integration"
	"github.com/onsi/gomega"
	"github.com/twitchtv/twirp"
)

func Test_Product_Create_Products(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	newProduct := &proto.Product{
		Name:                 "actions",
		FriendlyProductName:  "Actions",
		ZuoraUsageIdentifier: "actions-zuora-usage-identifier",
	}
	createResponse, err := client.UpsertProduct(newProduct)

	g.Expect(createResponse.Product.Name).To(gomega.Equal("actions"))
	g.Expect(createResponse.Product.FriendlyProductName).To(gomega.Equal("Actions"))
	g.Expect(createResponse.Product.ZuoraUsageIdentifier).To(gomega.Equal("actions-zuora-usage-identifier"))

	g.Expect(err).To(gomega.BeNil())

	getResponse, err := client.GetProduct("actions")
	g.Expect(err).ToNot(gomega.HaveOccurred())
	g.Expect(getResponse.Product.Name).To(gomega.Equal("actions"))
	g.Expect(getResponse.Product.FriendlyProductName).To(gomega.Equal("Actions"))
	g.Expect(getResponse.Product.ZuoraUsageIdentifier).To(gomega.Equal("actions-zuora-usage-identifier"))
}

func Test_Product_Get_Products(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	allProductsResponseBeforeInserting, _ := client.GetAllProducts()
	g.Expect(len(allProductsResponseBeforeInserting.Products)).To(gomega.Equal(0))

	actions := &proto.Product{
		Name:                 "actions",
		FriendlyProductName:  "Actions",
		ZuoraUsageIdentifier: "actions-zuora-usage-identifier",
	}

	codespaces := &proto.Product{
		Name:                 "codespaces",
		FriendlyProductName:  "Codespaces",
		ZuoraUsageIdentifier: "codespaces-zuora-usage-identifier",
	}

	_, _ = client.UpsertProduct(actions)
	_, _ = client.UpsertProduct(codespaces)

	allProductsResponse, _ := client.GetAllProducts()
	g.Expect(len(allProductsResponse.Products)).To(gomega.Equal(2))

	returnedProducts := []string{}
	for _, product := range allProductsResponse.Products {
		returnedProducts = append(returnedProducts, product.Name)
	}

	g.Expect(returnedProducts).To(gomega.Equal([]string{
		"actions",
		"codespaces",
	}))
}

func Test_Product_Get_Empty_Product(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	_, err := client.GetProduct("actions")
	g.Expect(err).To(gomega.Equal(twirp.NotFoundError("Product not found")))
}

func Test_Product_Update_Product(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	actions := &proto.Product{
		Name:                 "actions",
		FriendlyProductName:  "Actions",
		ZuoraUsageIdentifier: "actions-zuora-usage-identifier",
	}
	_, _ = client.UpsertProduct(actions)

	response, getErr := client.GetProduct("actions")
	g.Expect(getErr).ToNot(gomega.HaveOccurred())
	updatedProduct := response.Product
	updatedProduct.FriendlyProductName = "Actions 2.0"
	_, err := client.UpsertProduct(updatedProduct)
	g.Expect(err).To(gomega.BeNil())

	allProductsResponse, _ := client.GetAllProducts()
	g.Expect(len(allProductsResponse.Products)).To(gomega.Equal(1))
	g.Expect(allProductsResponse.Products[0].FriendlyProductName).To(gomega.Equal("Actions 2.0"))
}
