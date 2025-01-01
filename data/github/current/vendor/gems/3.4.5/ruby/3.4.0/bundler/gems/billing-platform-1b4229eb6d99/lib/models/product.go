package models

import "github.com/github/billing-platform/lib/twirp/proto"

// TODO: We really need to sort out naming conflicts with "Product". I also experienced this in my last PR. Will address in this PR.
type Product struct {
	*Key
	Name                 string
	FriendlyProductName  string
	ZuoraUsageIdentifier string
}

func NewProductKey(productName string) *Key {
	return &Key{
		Id:           productName,
		PartitionKey: "product",
	}
}

// Product and Sku are immutable and therefore can be used as the primary key
// for lookups and queries. Friendly names can be updated.
func NewProduct(product string, friendlyProductName string, zuoraUsageIdentifier string) *Product {
	return &Product{
		Key:                  NewProductKey(product),
		Name:                 product,
		FriendlyProductName:  friendlyProductName,
		ZuoraUsageIdentifier: zuoraUsageIdentifier,
	}
}

func (product *Product) ToProto() *proto.Product {
	return &proto.Product{
		Name:                 product.Name,
		FriendlyProductName:  product.FriendlyProductName,
		ZuoraUsageIdentifier: product.ZuoraUsageIdentifier,
	}
}
