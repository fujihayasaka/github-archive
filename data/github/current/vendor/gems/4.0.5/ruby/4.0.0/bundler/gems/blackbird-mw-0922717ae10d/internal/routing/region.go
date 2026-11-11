package routing

// Region is a custom type that represents the region that a cluster is provisioned in.
type Region int

const (
	// In dotcom, this is effectively eastus. In proxima it is the corresponding Azure region.
	DefaultRegion Region = iota
	// Central US
	GCCUS02
)

// Use the SitesAPI if you need access to the actual regions. This is a shortcut for mapping regions to Kafka brokers.
func (r Region) String() string {
	return [...]string{"default", "centralus"}[r]
}

// ClusterResolver resolves Kafka brokers and regions based on Blackbird cluster names.
//
// NOTE: This only handles the Go/sarama code. Code that uses the client clib uses the toml config, which must have an
// equivalent mapping in it.
//
// The values in this struct are expected to be consistent with each other.
type ClusterResolver struct {
	// Mapping from a region to a list of Kafka brokers.
	brokers map[Region][]string
	// Mapping from a Blackbird cluster name to a Region. The lack of an entry for a cluster means it is in the default
	// region.
	regions map[string]Region
}

// NewClusterResolver returns a ClusterResolver.
func NewClusterResolver(brokers map[Region][]string, regions map[string]Region) ClusterResolver {
	return ClusterResolver{brokers, regions}
}

// GetBrokers returns the brokers for the given cluster. If none is found, returns the brokers for the default region.
func (k ClusterResolver) GetBrokers(cluster string) []string {
	return k.brokers[k.GetRegion(cluster)]
}

// GetRegion returns the region for the given cluster. If none is found, returns the default region.
func (k ClusterResolver) GetRegion(cluster string) Region {
	if region, ok := k.regions[cluster]; ok {
		return region
	}
	return DefaultRegion
}

// AllBrokers returns a map of regions/sites, where each entry is a list of Kafka brokers.
func (k ClusterResolver) AllBrokers() map[Region][]string {
	return k.brokers
}
