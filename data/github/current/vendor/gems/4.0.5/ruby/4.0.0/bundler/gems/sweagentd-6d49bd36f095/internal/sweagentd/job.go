package sweagentd

// JobCounts represents the counts of jobs in different states.
type JobCounts struct {
	Queued  int
	Running int
}

// OwnerType represents whether the repository owner is a user or an organization.
type OwnerType string

const (
	// OwnerTypeUser indicates the repository owner is a GitHub user.
	OwnerTypeUser OwnerType = "User"
	// OwnerTypeOrganization indicates the repository owner is a GitHub organization.
	OwnerTypeOrganization OwnerType = "Organization"
)
