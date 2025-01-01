package freno

// Tip: You can use `..mysql table-where <table-name>` to determine the cluster for a resource
const (
	AppName = "launch"
	DBType  = "mysql"

	LaunchDBCluster = "launch"
	// Installation tokens are stored in the `permissions` table
	InstallationTokensDBCluster = "permissions"
	EnvironmentsDBCluster       = "repositories"
	ChecksDBCluster             = "repositories-actions-checks"
	WorkflowRunsDBCluster       = "repositories-actions-checks"
)
