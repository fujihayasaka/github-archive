package models

import (
	"fmt"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/twirp/proto"
)

type EntityDetail struct {
	CustomerId       string
	OrganizationId   int64 `json:",omitempty"`
	RepositoryId     int64 `json:",omitempty"`
	ActorId          int64 `json:",omitempty"`
	CostCenterDetail *CostCenterDetail
}

// IsGitHubOwned returns true if the entity/owning entity is  GitHubInc or Avocado Corp.
func (entityDetail *EntityDetail) IsGitHubOwned() bool {
	enterpriseId := entityDetail.EnterpriseId()
	return enterpriseId == "1061737" ||
		enterpriseId == "5018891" ||
		entityDetail.CustomerId == "1061737" ||
		entityDetail.CustomerId == "5018891"
}

func (entityDetail *EntityDetail) SetCostCenterDetail(costCenterDetail *CostCenterDetail) {
	if costCenterDetail != nil {
		entityDetail.CostCenterDetail = costCenterDetail
		entityDetail.CustomerId = costCenterDetail.GetCustomerId()
	}
}

func (entityDetail *EntityDetail) EnterpriseId() string {
	return entityDetail.CostCenterDetail.EnterpriseCustomerId
}

func (entityDetail *EntityDetail) GetCustomerId() string {
	if entityDetail.CostCenterDetail != nil {
		return entityDetail.CostCenterDetail.GetCustomerId()
	}
	return ""
}

func (entityDetail *EntityDetail) IsCostCenterProxy() bool {
	return entityDetail.CostCenterDetail != nil && entityDetail.CostCenterDetail.IsCostCenterProxy
}

func NewEntityDetail(entityDetail *proto.EntityDetail) *EntityDetail {
	return newEntityDetail(entityDetail.GetCustomerId(), entityDetail.GetOwnerId(), entityDetail.GetRepoId(), entityDetail.GetActorId())
}

func NewEntityDetailFromCostCenterDetail(costCenterDeatil *CostCenterDetail) *EntityDetail {
	entityDetail := newEntityDetail("", 0, 0, 0)
	entityDetail.SetCostCenterDetail(costCenterDeatil)
	return entityDetail
}

func NewEntityDetailFromHydro(message hydroSchema.EntityDetail) *EntityDetail {
	return newEntityDetail(fmt.Sprintf("%d", message.CustomerId), message.OrganizationId, message.RepoId, message.ActorId)
}

func newEntityDetail(customerId string, organizationId int64, repositoryId int64, actorId int64) *EntityDetail {
	return &EntityDetail{
		CustomerId:     customerId,
		OrganizationId: organizationId,
		RepositoryId:   repositoryId,
		ActorId:        actorId,
		CostCenterDetail: &CostCenterDetail{
			EnterpriseCustomerId: customerId,
		},
	}
}
