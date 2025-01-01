package models

import (
	"testing"

	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
)

func TestNewCustomer(t *testing.T) {
	customer := NewCustomer(1, SdlcLicensingModel(0), false)

	assert.Equal(t, uint64(1), customer.IDToUInt64())
	assert.Equal(t, SdlcLicensingModel(0), customer.SdlcLicensingModel)
	assert.Equal(t, "Customer", customer.PartitionKey)
	assert.False(t, customer.SdlcTrial)
}

func TestNewCustomerFromProto(t *testing.T) {
	proto := stubs.NewCustomerProto()
	customer := NewCustomerFromProto(proto)

	assert.Equal(t, proto.Id, customer.IDToUInt64())
	assert.Equal(t, proto.SdlcLicensingModel, customer.SdlcLicensingModel.ToProto())
	assert.Equal(t, proto.SdlcTrial, customer.SdlcTrial)
	assert.Equal(t, "Customer", customer.PartitionKey)
}

func TestCustomerToProto(t *testing.T) {
	customerID := uint64(1)
	customer := NewCustomer(customerID, LicensingModelMetered, true)
	proto := customer.ToProto()

	assert.Equal(t, customerID, proto.Id)
	assert.Equal(t, LicensingModelMetered.ToProto(), proto.SdlcLicensingModel)
	assert.True(t, proto.SdlcTrial)
}

func TestIsSdlcMetered(t *testing.T) {
	customer := NewCustomer(1, LicensingModelMetered, false)
	assert.True(t, customer.IsSdlcMetered())
}

func TestIsSdlcMeteredFalse(t *testing.T) {
	customer := NewCustomer(1, LicensingModelVolume, false)
	assert.False(t, customer.IsSdlcMetered())
}
