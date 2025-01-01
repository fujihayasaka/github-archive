package models

// DeleteOrganizationJob is a job to delete an organization from a customer's licenses.
type DeleteOrganizationJob struct {
	CustomerID     uint64
	OrganizationID uint64
}
