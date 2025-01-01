package aqueduct

// Queue names
const (
	QueueNotify                   = "notifyd_notify"
	QueueDeliverMobilePush        = "notifyd_deliver_mobile_push"
	QueueDeliverEmail             = "notifyd_deliver_email"
	QueueDeleteRepository         = "notifyd_delete_repository"
	QueueDeleteUser               = "notifyd_delete_user"
	QueueDeleteUserRepositories   = "notifyd_delete_user_repositories"
	QueueDeleteRepositoryForUsers = "notifyd_delete_repository_for_users"
)

// ClientConfig defines the parameters necessary for an aqueduct client to work.
type ClientConfig struct {
	// App is the name we use to identify ourselves against aqueduct
	App string `config:",env=AQUEDUCT_APP"`

	// URL specifies the host for aqueduct so that the retries worker can work.
	URL string `config:"http://localhost:8085,env=AQUEDUCT_URL"`

	// APIKey and ApiKeyVersion are used to configure aqueduct auth.
	APIKey        string `config:",env=AQUEDUCT_API_KEY"`
	APIKeyVersion int    `config:"0,env=AQUEDUCT_API_KEY_VERSION"`
}

// WorkerConfig defines the parameters necessary for an aqueduct worker to work.
//
// TODO(abeaumont): AQUEDUCT_APP and AQUEDUCT_QUEUE should be hardcoded if we have
// a binary per worker. AQUEDUCT_PARALLEL_JOBS is a pool variable, not a worker one.
type WorkerConfig struct {
	// App is the name we use to identify ourselves against aqueduct. This is parametrized via env
	// vars because it changes depending with the env. For example, in staging we use notifyd-staging
	App string `config:",env=AQUEDUCT_APP"`

	// Queue from which a worker will pull jobs to process.
	Queue string `config:",env=AQUEDUCT_QUEUE"`

	// ParallelJobs specifies how many jobs can this worker handle in parallel.
	ParallelJobs int `config:"1,env=AQUEDUCT_PARALLEL_JOBS"`
}

// GetApp returns the app name.
func (wg WorkerConfig) GetApp() string {
	return wg.App
}

// GetQueue returns the queue name.
func (wg WorkerConfig) GetQueue() string {
	return wg.Queue
}

// GetParallelJobs returns the number of parallel jobs.
func (wg WorkerConfig) GetParallelJobs() int {
	return wg.ParallelJobs
}
