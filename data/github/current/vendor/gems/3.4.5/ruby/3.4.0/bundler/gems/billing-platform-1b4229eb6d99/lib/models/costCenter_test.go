package models

import (
	"testing"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/stretchr/testify/assert"
)

//////////////////////////////////////////////////
//						models#NewCostCenter							//
//////////////////////////////////////////////////

func Test_CostCenter_NewCostCenter_HasCostCenterState(t *testing.T) {
	protoCostCenterKey := &proto.CostCenterKey{
		CustomerId: "123",
		Uuid:       "uuid",
	}

	protoCostCenter := &proto.CostCenter{
		CostCenterKey:   protoCostCenterKey,
		Name:            "test",
		CostCenterState: proto.CostCenterState_CostCenterActive,
	}

	costCenter := NewCostCenter(protoCostCenter, false)

	assert.Equal(t, costCenter.CostCenterState, CostCenterActive)
}

//////////////////////////////////////////////////
//						models#Validate							//
//////////////////////////////////////////////////

func Test_CostCenter_Validate_ValidatesNameUniqueness(t *testing.T) {
	costCenterToValidate := NewCostCenter(&proto.CostCenter{
		Name: "New Cost Center",
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: "1",
			TargetId:   "1234",
			TargetType: proto.CostCenterType_AzureSubscription,
		},
		Resources: []*proto.Resource{
			{Id: "3", Type: proto.ResourceType_Org},
		},
	}, true)

	costCenterWithSameName := NewCostCenter(&proto.CostCenter{
		Name: "New Cost Center",
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: "1",
			TargetId:   "5678",
			TargetType: proto.CostCenterType_AzureSubscription,
		},
		Resources: []*proto.Resource{
			{Id: "1", Type: proto.ResourceType_Repo},
		},
	}, true)

	costCenterWithDifferentName := NewCostCenter(&proto.CostCenter{
		Name: "Other Cost Center",
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: "1",
			TargetId:   "5678",
			TargetType: proto.CostCenterType_AzureSubscription,
		},
		Resources: []*proto.Resource{
			{Id: "1", Type: proto.ResourceType_Repo},
		},
	}, true)

	err := costCenterToValidate.Validate([]*CostCenter{costCenterWithSameName})
	assert.NotNil(t, err)
	assert.Equal(t, err.Error(), "a cost center with that name already exists: conflict")

	err = costCenterToValidate.Validate([]*CostCenter{costCenterWithDifferentName})
	assert.Nil(t, err)
}

func Test_CostCenter_Validate_DoesNotValidateTargetUniquenessWhenTargetIdBlank(t *testing.T) {
	costCenterToValidate := NewCostCenter(&proto.CostCenter{
		Name: "New Cost Center",
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: "1",
			TargetId:   "",
			TargetType: proto.CostCenterType_AzureSubscription,
		},
		Resources: []*proto.Resource{
			{Id: "3", Type: proto.ResourceType_Org},
		},
	}, true)

	costCenterWithSameTarget := NewCostCenter(&proto.CostCenter{
		Name: "Other Cost Center",
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: "1",
			TargetId:   "",
			TargetType: proto.CostCenterType_AzureSubscription,
		},
		Resources: []*proto.Resource{
			{Id: "1", Type: proto.ResourceType_Repo},
		},
	}, true)

	err := costCenterToValidate.Validate([]*CostCenter{costCenterWithSameTarget})
	assert.Nil(t, err)
}

func Test_CostCenter_Validate_ValidatesResourceUniqueness(t *testing.T) {
	costCenterToValidate := NewCostCenter(&proto.CostCenter{
		Name: "New Cost Center",
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: "1",
			TargetId:   "1234",
			TargetType: proto.CostCenterType_AzureSubscription,
		},
		Resources: []*proto.Resource{
			{Id: "3", Type: proto.ResourceType_Org},
		},
	}, true)

	costCenterWithResourceOverlap := NewCostCenter(&proto.CostCenter{
		Name: "Other Cost Center",
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: "1",
			TargetId:   "5678",
			TargetType: proto.CostCenterType_AzureSubscription,
		},
		Resources: []*proto.Resource{
			{Id: "3", Type: proto.ResourceType_Org},
		},
	}, true)

	costCenterWithNoResourceOverlap := NewCostCenter(&proto.CostCenter{
		Name: "Other Cost Center v2",
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: "1",
			TargetId:   "5678",
			TargetType: proto.CostCenterType_AzureSubscription,
		},
		Resources: []*proto.Resource{
			{Id: "10", Type: proto.ResourceType_Org},
		},
	}, true)

	err := costCenterToValidate.Validate([]*CostCenter{costCenterWithResourceOverlap})
	assert.NotNil(t, err)
	assert.Equal(t, err.Error(), "one or more selected resources are already in use by cost center Other Cost Center: conflict")

	err = costCenterToValidate.Validate([]*CostCenter{costCenterWithNoResourceOverlap})
	assert.Nil(t, err)
}
