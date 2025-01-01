package azp

// RepositoryClient is responsible for communicating with the Actions Runtime
// on behalf of a user (repository in this case).
type RepositoryClient interface {
	BuildsClient
	URLExchangeClient
	RunnersClient
	RunnerGroupsClient
	RunnerScaleSetsClient
	ArtifactsClient
	LabelsClient
	GatesClient
	LargerRunnersClient
	ChecksClient
	ArtifactCacheClient
}
