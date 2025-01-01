package models

import (
	"fmt"
	"strconv"

	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
)

// Customer for storing customer information and enable querying customer licenses
type Customer struct {
	*Key
	CosmosProperties
	SdlcLicensingModel SdlcLicensingModel `json:"sdlcLicensingModel"`
	SdlcTrial          bool               `json:"sdlcTrial"`
}

// CustomerPartitionKey is the partition key for a Customer.
const CustomerPartitionKey = "Customer"

// NewCustomer creates a new customer
func NewCustomer(id uint64, sdlcLicensingModel SdlcLicensingModel, sdlcTrial bool) *Customer {
	return &Customer{
		Key:                NewCustomerKey(id),
		SdlcLicensingModel: sdlcLicensingModel,
		SdlcTrial:          sdlcTrial,
	}
}

// NewCustomerFromProto creates a new customer from a proto.Customer
func NewCustomerFromProto(input *proto.Customer) *Customer {
	return &Customer{
		Key:                NewCustomerKey(input.Id),
		SdlcLicensingModel: SdlcLicensingModel(input.SdlcLicensingModel),
		SdlcTrial:          input.SdlcTrial,
	}
}

// NewCustomerKey creates a new Key for a Customer.
//
// pk format: Customer
// id format: {id}
func NewCustomerKey(id uint64) *Key {
	return &Key{
		PartitionKey: CustomerPartitionKey,
		ID:           fmt.Sprintf("%d", id),
	}
}

// ToProto converts the Customer to a proto.Customer.
func (customer *Customer) ToProto() *proto.Customer {
	return &proto.Customer{
		Id:                 customer.IDToUInt64(),
		SdlcLicensingModel: customer.SdlcLicensingModel.ToProto(),
		SdlcTrial:          customer.SdlcTrial,
	}
}

// IsValid checks if the Customer has valid fields returns list of invalid fields.
func (customer *Customer) IsValid() []string {
	strings := make([]string, 0)

	if customer.ID == "0" || customer.ID == "" {
		strings = append(strings, "id")
	}
	if customer.SdlcLicensingModel == LicensingModelUnspecified {
		strings = append(strings, "sdlcLicensingModel")
	}

	return strings
}

// IsSdlcMetered returns true if the customer SDLC licensing model is metered.
func (customer *Customer) IsSdlcMetered() bool {
	return customer.SdlcLicensingModel == LicensingModelMetered
}

// HasHighWatermarkSdlcLicensing returns true if the customer's licenses should be treated as high watermark.
func (customer *Customer) HasHighWatermarkSdlcLicensing() bool {
	return customer.IsSdlcMetered() && !customer.SdlcTrial
}

// IDToUInt64 converts the string ID to a uint64.
func (customer *Customer) IDToUInt64() uint64 {
	id, err := strconv.ParseUint(customer.ID, 10, 64)
	if err != nil {
		return 0
	}
	return id
}
