package models

import (
	"testing"

	entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/twirp/proto"
)

func Test_GettingCustomerId(t *testing.T) {
	entity := entities.EntityDetail{
		CustomerId: 123,
	}
	entityDetail := NewEntityDetailFromHydro(entity)

	protoCostCenterKey := &proto.CostCenterKey{
		CustomerId: "123",
		Uuid:       "uuid",
	}
	costCenterKey := NewCostCenterKey(protoCostCenterKey, false)
	detail := NewCustomerFromCostCenter(costCenterKey).CostCenterDetail
	entityDetail.SetCostCenterDetail(detail)

	if entityDetail.CustomerId != "uuid" {
		t.Errorf("expected entity.CustomerId to be uuid, got %s", entityDetail.CustomerId)
	}

	if entityDetail.EnterpriseId() != "123" {
		t.Errorf("expected entity.EnterpriseId to be 123, got %s", entityDetail.EnterpriseId())
	}

	if entityDetail.GetCustomerId() != "uuid" {
		t.Errorf("expected entity.GetCustomerId() to be uuid, got %s", entityDetail.GetCustomerId())
	}
}

func Test_GettingCustomerIdWhenIsCostCenterProxy_AndCostCenterDetailIsSet(t *testing.T) {
	entity := entities.EntityDetail{
		CustomerId: 123,
	}
	entityDetail := NewEntityDetailFromHydro(entity)

	protoCostCenterKey := &proto.CostCenterKey{
		CustomerId: "123",
		Uuid:       "uuid",
	}
	costCenterKey := NewCostCenterKey(protoCostCenterKey, false)
	// manually setting the IsCostCenterProxy to replicate reading from the db
	costCenterKey.Customer.CostCenterDetail.IsCostCenterProxy = true
	costCenterKey.Customer.CostCenterDetail.EnterpriseCustomerId = "123"
	costCenterKey.Customer.CostCenterDetail.CostCenterUUID = "uuid"
	detail := NewCustomerFromCostCenter(costCenterKey).CostCenterDetail
	entityDetail.SetCostCenterDetail(detail)

	if entityDetail.CustomerId != "uuid" {
		t.Errorf("expected entity.CustomerId to be uuid, got %s", entityDetail.CustomerId)
	}

	if entityDetail.EnterpriseId() != "123" {
		t.Errorf("expected entity.EnterpriseId to be 123, got '%s'", entityDetail.EnterpriseId())
	}

	if entityDetail.GetCustomerId() != "uuid" {
		t.Errorf("expected entity.GetCustomerId() to be uuid, got %s", entityDetail.GetCustomerId())
	}
}
