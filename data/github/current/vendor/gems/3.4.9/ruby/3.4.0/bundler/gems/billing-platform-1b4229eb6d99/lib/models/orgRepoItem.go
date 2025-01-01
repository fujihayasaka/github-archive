package models

import "github.com/github/billing-platform/lib/twirp/proto"

type OrgRepoItem struct {
	*Amounts
	RepositoryId   int64 `json:"repositoryId"`
	OrganizationId int64 `json:"organizationId"`
}

func (orgRepoItem *OrgRepoItem) ToProto() *proto.OrgRepoItem {
	billedAmount := float64(0)
	if orgRepoItem.Amounts != nil {
		amounts := orgRepoItem.Amounts.ToDecimal()
		billedAmount = amounts.BilledAmount
	}

	return &proto.OrgRepoItem{
		RepoId:       orgRepoItem.RepositoryId,
		OrgId:        orgRepoItem.OrganizationId,
		BilledAmount: billedAmount,
	}
}
