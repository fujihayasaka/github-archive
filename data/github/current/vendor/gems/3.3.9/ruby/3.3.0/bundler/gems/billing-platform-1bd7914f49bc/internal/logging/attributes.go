package logging

/*
Collection of common billing related Open Telemetry attributes for re-use when logging.

See https://thehub.github.com/epd/engineering/dev-practicals/observability/logging/opentelemetry-logging/#resource-and-attribute-names
for information on attribute naming conventions.
*/
const (
	BillingCustomerId             = "gh.billing.customer.id"
	BillingPlatformCostCenterUUID = "gh.billing_platform.cost_center.uuid"
	BillingPlatformCostCenterName = "gh.billing_platform.cost_center.name"
)
