package models

import (
	"fmt"
	"time"

	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// ProductEnablement represents a product enablement.
type ProductEnablement struct {
	*Key
	CosmosProperties
	CustomerID     uint64 `json:"CustomerId"`
	Product        Product
	EnablementID   uint64
	EnablementType ProductEnablementType
	GlobalID       string
	EnabledAt      int64
}

// NewProductEnablementFromProto creates a new ProductEnablement from a proto.ProductEnablement.
func NewProductEnablementFromProto(input *proto.ProductEnablement) *ProductEnablement {
	return &ProductEnablement{
		Key:            NewProductEnablementKeyFromProto(input),
		CustomerID:     input.CustomerId,
		Product:        Product(input.Product),
		EnablementID:   input.EnablementId,
		EnablementType: ProductEnablementType(input.EnablementType),
		GlobalID:       input.GlobalId,
		EnabledAt:      input.EnabledAt.AsTime().Unix(),
	}
}

// ToProto converts the ProductEnablement to a proto.ProductEnablement.
func (pe *ProductEnablement) ToProto() *proto.ProductEnablement {
	return &proto.ProductEnablement{
		CustomerId:     pe.CustomerID,
		Product:        pe.Product.ToProto(),
		EnablementId:   pe.EnablementID,
		EnablementType: pe.EnablementType.ToProto(),
		GlobalId:       pe.GlobalID,
		EnabledAt:      timestamppb.New(time.Unix(pe.EnabledAt, 0)),
	}
}

const pkProductEnablement = "ProductEnablement"

// NewProductEnablementPartitionKey creates a partition key for a ProductEnablement.
func NewProductEnablementPartitionKey(customerID uint64) string {
	return fmt.Sprintf("%d/%s", customerID, pkProductEnablement)
}

// NewProductEnablementKeyFromProto creates a new Key for a ProductEnablement from a proto.
func NewProductEnablementKeyFromProto(input *proto.ProductEnablement) *Key {
	pk := NewProductEnablementPartitionKey(input.CustomerId)
	id := fmt.Sprintf("%s:%s:%d",
		Product(input.Product),
		ProductEnablementType(input.EnablementType),
		input.EnablementId,
	)
	return &Key{
		PartitionKey: pk,
		ID:           id,
	}
}
