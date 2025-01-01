package logging

/*
Collection of common billing related Open Telemetry attributes for re-use when logging.

See https://thehub.github.com/epd/engineering/dev-practicals/observability/logging/opentelemetry-logging/#resource-and-attribute-names
for information on attribute naming conventions.
*/
const (
	BillingCustomerId             = "gh.customer.id"
	BillingPlatformUsageItemUUID  = "gh.billing_platform.usage_item.uuid"
	BillingPlatformCostCenterUUID = "gh.billing_platform.cost_center.uuid"
	BillingPlatformCostCenterName = "gh.billing_platform.cost_center.name"
	BillingPlatformPartitionKey   = "gh.billing_platform.partition_key"
	CustomerPlanName              = "gh.customer.plan.name"
	BillingCustomerPreviousId     = "gh.customer.previous_customer_id"
	DiscountStateTargetAmount     = "gh.customer.discount_state.target_amount"
	DiscountStateCurrentAmount    = "gh.customer.discount_state.current_amount"
	DiscountStateIsFullyApplied   = "gh.customer.discount_state.is_fully_applied"
	RepositoryId                  = "gh.repo.id"
	OrganizationId                = "gh.org.id"
	BillingPlatformProduct        = "gh.billing_platform.product"
	BillingPlatformSku            = "gh.billing_platform.sku"
	BillingPlatformGroupBy        = "gh.billing_platform.group_by"
	BillingOrgAdminRequest        = "gh.billing_platform.org_admin_request"
)
