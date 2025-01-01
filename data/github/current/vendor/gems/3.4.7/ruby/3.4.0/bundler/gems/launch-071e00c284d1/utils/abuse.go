package utils

import (
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
)

func GetHydroBillingPlanOwnerType(typeName string) hydroV0.BillingPlanOwner_Type {
	switch typeName {
	case "User":
		return hydroV0.BillingPlanOwner_TYPE_USER
	case "Organization":
		return hydroV0.BillingPlanOwner_TYPE_ORGANIZATION
	case "Business":
		return hydroV0.BillingPlanOwner_TYPE_BUSINESS
	default:
		return hydroV0.BillingPlanOwner_TYPE_UNKNOWN
	}
}

func GetHydroBillingPlanOwnerSKU(planName string) hydroV0.BillingPlanOwner_SKU {
	switch planName {
	case "free":
		return hydroV0.BillingPlanOwner_SKU_FREE
	case "free_with_addons":
		return hydroV0.BillingPlanOwner_SKU_FREE
	case "enterprise":
		return hydroV0.BillingPlanOwner_SKU_ENTERPRISE
	case "business":
		return hydroV0.BillingPlanOwner_SKU_TEAM
	case "business_plus":
		return hydroV0.BillingPlanOwner_SKU_TEAM
	case "pro":
		return hydroV0.BillingPlanOwner_SKU_PRO
	default:
		return hydroV0.BillingPlanOwner_SKU_UNKNOWN
	}
}
