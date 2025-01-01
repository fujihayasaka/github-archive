// Package queues contains the names of the queues that the aqueduct workers can process.
package queues

const (
	// QueueSyncOrgMemberships is the queue for syncing org memberships.
	QueueSyncOrgMemberships = "licensify_sync_org_memberships"
	// QueueBackfillSyncOrgMemberships is the queue for backfill syncs of org memberships.
	QueueBackfillSyncOrgMemberships = "licensify_backfill_sync_org_memberships"
	// QueueDeleteEnablements is the queue for deleting enablements.
	QueueDeleteEnablements = "licensify_delete_enablements"
	// QueueProductEnablementUpdated is the queue for updating product enablements.
	QueueProductEnablementUpdated = "licensify_product_enablement_updated"
	// QueueRepositoryDeleted is the queue for handling repository deleted events from aqueduct bridge.
	QueueRepositoryDeleted = "licensify_repository_deleted"
	// QueueRepositoryRestored is the queue for handling repository restored events from aqueduct bridge.
	QueueRepositoryRestored = "licensify_repository_restored"
	// QueueCreateRepositoryCollaborators is the queue for creating repository collaborators.
	QueueCreateRepositoryCollaborators = "licensify_create_repository_collaborators"
	// QueueScheduleEmissions is the queue for scheduling emissions.
	QueueScheduleEmissions = "licensify_schedule_emissions"
	// QueuePublishEmission is the queue for publishing emissions.
	QueuePublishEmission = "licensify_publish_emission"
	// QueueBackfillLicenseStatus is the queue for backfilling license status.
	QueueBackfillLicenseStatus = "licensify_backfill_license_status"
	// QueueUserDestroy is the queue for deleting users.
	QueueUserDestroy = "licensify_user_destroy"
)

// StandardPriorityQueues is a list of queues that are considered standard priority.
var StandardPriorityQueues = []string{
	QueueSyncOrgMemberships,
	QueueDeleteEnablements,
	QueueProductEnablementUpdated,
	QueueRepositoryDeleted,
	QueueRepositoryRestored,
	QueueCreateRepositoryCollaborators,
	QueueUserDestroy,
	QueueScheduleEmissions,
	QueuePublishEmission,
}

// LowPriorityQueues is a list of queues that are considered low priority.
var LowPriorityQueues = []string{
	QueueBackfillSyncOrgMemberships,
	QueueBackfillLicenseStatus,
}
