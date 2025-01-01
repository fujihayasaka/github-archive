package models

type UsagePartitionType byte

const (
	ByCustomerProduct           UsagePartitionType = 0 << iota
	BySku                       UsagePartitionType = 1
	ByCustomer                  UsagePartitionType = 2
	ByCustomerSku               UsagePartitionType = 3
	ByCustomerRepo              UsagePartitionType = 4
	ByCustomerOrg               UsagePartitionType = 5
	ByCustomerOrgRepo           UsagePartitionType = 6
	ByCustomerRepoByProductSku  UsagePartitionType = 7
	ByCustomerOrgByProductSku   UsagePartitionType = 9
	ByCustomerAzureEmission     UsagePartitionType = 10
	MissingCustomer             UsagePartitionType = 11
	ByCustomerAsEvent           UsagePartitionType = 12
	ByCustomerAsEventRollup     UsagePartitionType = 13
	ByCustomerOrgRepoProductSku UsagePartitionType = 14
	ByOrgRepoProductSku         UsagePartitionType = 15
	ByCustomerZuoraEmission     UsagePartitionType = 16
)
