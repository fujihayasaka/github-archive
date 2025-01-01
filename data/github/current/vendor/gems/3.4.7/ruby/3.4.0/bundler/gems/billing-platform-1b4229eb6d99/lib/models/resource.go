package models

import (
	"fmt"

	"github.com/github/billing-platform/lib/twirp/proto"
)

type ResourceType byte

const (
	NoTarget ResourceType = iota
	User
	Team
	Repository
	OwningEntity
	Enterprise
	CostCenterResource
	CustomerResource
)

func ToResourceType(t proto.ResourceType) ResourceType {
	return ResourceType(t)
}

func (b ResourceType) ToProto() proto.ResourceType {
	return proto.ResourceType(b)
}

func (b ResourceType) String() string {
	switch b {
	case User:
		return "user"
	case Team:
		return "team"
	case Repository:
		return "repository"
	case OwningEntity:
		return "owning_entity"
	case Enterprise:
		return "enterprise"
	case CostCenterResource:
		return "cost_center"
	case CustomerResource:
		return "customer"
	default:
		return fmt.Sprintf("%d", int(b))
	}
}

type Resource struct {
	Id   string
	Type ResourceType
}

func NewResourceWithNumericId(id int64, t ResourceType) *Resource {
	return NewResourceWith(fmt.Sprintf("%d", id), t)
}

func NewResourceWith(id string, t ResourceType) *Resource {
	return &Resource{
		Id:   id,
		Type: t,
	}
}
func NewResource(input *proto.Resource) *Resource {
	return NewResourceWith(input.Id, ToResourceType(input.Type))
}

func (r Resource) ToProto() *proto.Resource {
	return &proto.Resource{
		Id:   r.Id,
		Type: r.Type.ToProto(),
	}
}
