// Package tenancy provides all the tools to build and inspect tenants.
package tenancy

import "fmt"

// Config represents tenancy configuration.
type Config struct {
	IsMultiTenantEnv bool `config:"false,env=MULTI_TENANT_ENTERPRISE"`
}

/*
Tenant is an interface that allow us to pass any kind of concrete tenant implementation around.

A Tenant has two pieces of information:
  - The slug, used for subdomains in public urls
  - The ID, used for data isolation

Any struct that implements the interface provides methods to update these attributes
*/
type Tenant interface {
	// IsMultiTenant tells us if we are in a multi tenant environment
	IsMultiTenant() bool
	WithSlug(string) Tenant
	WithID(int64) Tenant
	Slug() string
	ID() int64
	// Given a base domain (like ghe.com), build the full domain name including
	// tenant subdomains if necessary
	BuildDomain(string) string
}

// NewTenant builds a concrete Tenant implementation based on the current environment
func NewTenant(cfg Config) Tenant {
	if cfg.IsMultiTenantEnv {
		return NewMultiTenant()
	}

	return NewSingleTenant()
}

// SingleTenant indicates that we are in an environment where only one tenant exists
// The most common single tenant environment is github.com (a.k.a Dotcom)
type SingleTenant struct{}

// IsMultiTenant returns false for SingleTenant
func (s SingleTenant) IsMultiTenant() bool {
	return false
}

// WithSlug returns the tenant for SingleTenant
func (s SingleTenant) WithSlug(_ string) Tenant {
	return s
}

// WithID returns the tenant for SingleTenant
func (s SingleTenant) WithID(_ int64) Tenant {
	return s
}

// Slug returns an empty string for SingleTenant
func (s SingleTenant) Slug() string {
	return ""
}

// ID returns 0 for SingleTenant
func (s SingleTenant) ID() int64 {
	return 0
}

// BuildDomain returns the base domain for SingleTenant
func (s SingleTenant) BuildDomain(base string) string {
	return base
}

// NewSingleTenant creates a new SingleTenant
func NewSingleTenant() Tenant {
	return SingleTenant{}
}

// MultiTenant indicates that we are in an environment where more that one tenant coexist
// In multi-tenant environments we need to know what is the current tenant,
// and that's the information this struct provides
type MultiTenant struct {
	slug string
	id   int64
}

// IsMultiTenant returns true for MultiTenant
func (m MultiTenant) IsMultiTenant() bool {
	return true
}

// WithSlug returns a tenant with the given slug
func (m MultiTenant) WithSlug(slug string) Tenant {
	return MultiTenant{slug: slug, id: m.ID()}
}

// WithID returns a tenant with the given ID
func (m MultiTenant) WithID(id int64) Tenant {
	return MultiTenant{slug: m.Slug(), id: id}
}

// Slug returns the slug of the tenant
func (m MultiTenant) Slug() string {
	return m.slug
}

// ID returns the ID of the tenant
func (m MultiTenant) ID() int64 {
	return m.id
}

// BuildDomain returns the full domain name for the tenant
func (m MultiTenant) BuildDomain(base string) string {
	return fmt.Sprintf("%s.%s", m.Slug(), base)
}

// NewMultiTenant creates a new MultiTenant
func NewMultiTenant() Tenant {
	return MultiTenant{}
}
