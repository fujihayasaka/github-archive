package handlers

// operation represents the operation performed on a cosmos document
type operation string

const (
	operationNotModified operation = ""
	operationUpdated     operation = "updated"
	operationCreated     operation = "created"
	operationDeleted     operation = "deleted"
	operationUpserted    operation = "upserted"
	operationDeactivated operation = "deactivated"
)
