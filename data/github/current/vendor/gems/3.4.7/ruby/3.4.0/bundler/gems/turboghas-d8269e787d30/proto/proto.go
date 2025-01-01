// Package proto extends the protobuf messages with additional methods.
package proto

import (
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
)

func (c *Cursor) Next(i uint32, maxValue uint64) *Cursor {
	next := c.GetOffset() + uint64(i)
	if next >= maxValue {
		return nil
	}
	return &Cursor{Offset: next}
}

func (req *GetOrganizationsRequest) GetEntityId() uint64 {
	return req.BusinessId
}

func (req *GetOrganizationsRequest) GetEntityType() v1.EntityType {
	return v1.EntityType_ENTITY_TYPE_BUSINESS
}

func (req *GetCommittersForBusinessRequest) GetEntityId() uint64 {
	return req.BusinessId
}

func (req *GetCommittersForBusinessRequest) GetEntityType() v1.EntityType {
	return v1.EntityType_ENTITY_TYPE_BUSINESS
}

func (req *GetCommittersForOwnerRequest) GetEntityId() uint64 {
	return req.OwnerId
}

func (req *GetCommittersForOwnerRequest) GetEntityType() v1.EntityType {
	return v1.EntityType_ENTITY_TYPE_USER
}

func (req *GetEnterpriseUsersRequest) GetEntityId() uint64 {
	return req.BusinessId
}

func (req *GetEnterpriseUsersRequest) GetEntityType() v1.EntityType {
	return v1.EntityType_ENTITY_TYPE_BUSINESS
}

func (req *GetRepositoriesRequest) GetEntityId() uint64 {
	return req.OwnerId
}

func (req *GetRepositoriesRequest) GetEntityType() v1.EntityType {
	return v1.EntityType_ENTITY_TYPE_USER
}

func SKU(v string) v1.SKU {
	switch v {
	case "ghas_licenses":
		return v1.SKU_SKU_GHAS_LICENSES
	case "ghas_code_security_licenses":
		return v1.SKU_SKU_GHAS_CODE_SECURITY_LICENSES
	case "ghas_secret_protection_licenses":
		return v1.SKU_SKU_GHAS_SECRET_PROTECTION_LICENSES
	case "ghas_seats":
		return v1.SKU_SKU_GHAS_SEATS
	}
	return v1.SKU_SKU_INVALID
}
