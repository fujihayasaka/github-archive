package models

// DeleteEnablementsJob is a job to delete an Enablement from a customer's licenses.
type DeleteEnablementsJob struct {
	CustomerID       uint64
	EnablementReason EnablementReason
	EnablementID     uint64
}
