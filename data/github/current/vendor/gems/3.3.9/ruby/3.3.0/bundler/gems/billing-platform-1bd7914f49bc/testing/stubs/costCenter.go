package stubs

import (
	"fmt"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/google/uuid"
)

// Create Cost Center

func CreateCostCenter(costCenterType proto.CostCenterType) *proto.CostCenter {
	return CreateCostCenterWithCustomerId(GetRandomId64AsString(), costCenterType)
}

func CreateAzureCostCenter() *proto.CostCenter {
	return CreateCostCenter(proto.CostCenterType_AzureSubscription)
}

func CreateZuoraCostCenter() *proto.CostCenter {
	return CreateCostCenter(proto.CostCenterType_ZuoraSubscription)
}

// Create Cost Center With Resources

func CreateCostCenterWithResources(costCenterType proto.CostCenterType, resources []*proto.Resource) *proto.CostCenter {
	return CreateCostCenterWithCustomerAndResources(GetRandomId64AsString(), costCenterType, resources)
}

func CreateAzureCostCenterWithResources(resources []*proto.Resource) *proto.CostCenter {
	return CreateCostCenterWithResources(proto.CostCenterType_AzureSubscription, resources)
}

func CreateZuoraCostCenterWithResources(resources []*proto.Resource) *proto.CostCenter {
	return CreateCostCenterWithResources(proto.CostCenterType_ZuoraSubscription, resources)
}

// CreateCostCenterWithCustomerAndResources

func CreateCostCenterWithCustomerAndResources(customerId string, costCenterType proto.CostCenterType, resources []*proto.Resource) *proto.CostCenter {
	return CreateCostCenterWithAll(customerId, costCenterType, false, "", resources)
}

func CreateAzureCostCenterWithCustomerAndResources(customerId string, resources []*proto.Resource) *proto.CostCenter {
	return CreateCostCenterWithAll(customerId, proto.CostCenterType_AzureSubscription, true, "", resources)
}

func CreateZuoraCostCenterWithCustomerAndResources(customerId string, resources []*proto.Resource) *proto.CostCenter {
	return CreateCostCenterWithAll(customerId, proto.CostCenterType_ZuoraSubscription, false, "", resources)
}

// Create Cost Center With Customer ID

func CreateCostCenterWithCustomerId(customerId string, costCenterType proto.CostCenterType) *proto.CostCenter {
	return CreateCostCenterWithAll(customerId, costCenterType, false, "", []*proto.Resource{})
}

func CreateAzureCostCenterWithCustomerId(customerId string) *proto.CostCenter {
	return CreateCostCenterWithCustomerId(customerId, proto.CostCenterType_AzureSubscription)
}

func CreateZuoraCostCenterWithCustomerId(customerId string) *proto.CostCenter {
	return CreateCostCenterWithCustomerId(customerId, proto.CostCenterType_ZuoraSubscription)
}

// Create Azure Cost Center With Target ID
func CreateAzureCostCenterWithCustomerIdAndTargetId(customerId string) *proto.CostCenter {
	return CreateCostCenterWithAll(customerId, proto.CostCenterType_AzureSubscription, true, "", []*proto.Resource{})
}

// Create Cost Center From Scratch

func CreateCostCenterWithAll(customerId string, targetType proto.CostCenterType, setTargetId bool, name string, resources []*proto.Resource) *proto.CostCenter {
	// Zuora customers cannot add a targetId and it's optional for Azure customers, so we only set one if necessary for the test.
	targetId := ""
	if setTargetId {
		targetId = uuid.NewString()
	}

	if name == "" {
		name = fmt.Sprintf("Test_Cost_Center_%s", GetRandomId64AsString())
	}

	if resources == nil {
		resources = []*proto.Resource{}
	}

	return &proto.CostCenter{
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: customerId,
			TargetType: targetType,
			TargetId:   targetId,
		},
		Name:      name,
		Resources: resources,
	}
}
