package archive

import (
	"sync"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// ResourceCollector provides a threadsafe way to collect a resource list.
type ResourceCollector struct {
	resources []*v1.Resource
	m         sync.Mutex
}

// NewResourceCollector constructs a ResourceCollector.
func NewResourceCollector() *ResourceCollector {
	return &ResourceCollector{
		resources: []*v1.Resource{},
		m:         sync.Mutex{},
	}
}

// Add adds a single resource.
func (c *ResourceCollector) Add(resource *v1.Resource) {
	c.m.Lock()
	defer c.m.Unlock()
	c.resources = append(c.resources, resource)
}

// AddAll appends a list of resources.
func (c *ResourceCollector) AddAll(resources []*v1.Resource) {
	c.m.Lock()
	defer c.m.Unlock()
	c.resources = append(c.resources, resources...)
}

// GetResources returns the underlying resource list.
func (c *ResourceCollector) GetResources() []*v1.Resource {
	c.m.Lock()
	defer c.m.Unlock()
	return c.resources
}
