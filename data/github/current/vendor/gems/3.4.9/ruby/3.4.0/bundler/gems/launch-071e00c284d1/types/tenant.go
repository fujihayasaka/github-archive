package types

// RepositoryTenants contains the names of the tenants associated with this Repository
// OwnerTenantName and BillingPlanOwnerTenant name will usually be the same.
// Unless this repository is paid for by a Business account (enterprise).
// OwnerTenantID and BillingPlanOwnerTenantID are corresponding host ids
type RepositoryTenants struct {
	OwnerTenantID              string
	OwnerTenantName            string
	OwnerTenantURL             string
	BillingPlanOwnerTenantID   string
	BillingPlanOwnerTenantName string
	BillingPlanOwnerTenantURL  string
	BillingPlanOwnerType       string
}
