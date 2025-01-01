package models

import (
	"fmt"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
)

const (
	PartitionKeyDelimiter = ":"

	DocumentIdTotal           = "total"
	DocumentIdBudgetState     = "budgetState"
	DocumentIdResourceLookup  = "resourceLookup"
	InternallyProcessedEvent  = "InternallyProcessedEvent"
	RollOverFromPreviousMonth = "RollOverFromPreviousMonth"
	Charge                    = "Charge"
)

type ItemKey interface {
	GetKey() *Key
	CloneWithId(id string) *Key
	GetPartitionTemplate() string
	GetProductFromPartitionKey() string
	GetProductSkuFromPartitionKey() string
}

type Key struct {
	PartitionKey string `json:"partitionKey"`
	Id           string `json:"id"`
}

func (key *Key) GetKey() *Key {
	return key
}

func (key *Key) CloneWithId(id string) *Key {
	return &Key{
		PartitionKey: key.PartitionKey,
		Id:           id,
	}
}

func (key *Key) GetLoggerFields() []kvp.Field {
	return []kvp.Field{
		kvp.String("db.cosmosdb.partition_key", key.PartitionKey),
		kvp.String("db.cosmosdb.document_id", key.Id),
	}
}

type CosmosProperties struct {
	Timestamp int64  `json:"_ts"`
	ETag      string `json:"_etag"`
}

type TotalItem struct {
	*AmountsItem
	*CosmosProperties
	IsTotal bool
}

// this stops recursive calls to our custom unmarshaler
type UnmarshalAbleItem Item

// this holds the old fields that we don't want around anymore
// essentially makes them read only
type migratedItem struct {
	*UnmarshalAbleItem
	Sku     string
	Product string
}

func NewKeyFromPartitionKey(partitionKey string) *Key {
	return &Key{
		PartitionKey: partitionKey,
	}
}

func GetPartitionKey(billingItem *Item, upt UsagePartitionType, t ActiveType) string {
	usageTime := billingItem.UsageAt.ToPartitionKey(t)
	customerId := billingItem.GetCustomerId()

	switch upt {
	case BySku:
		return fmt.Sprintf("%s:%s", billingItem.GetSku(), usageTime)
	case ByCustomer:
		return fmt.Sprintf("%s:%s", customerId, usageTime)
	case ByCustomerOrgRepo:
		return fmt.Sprintf("%s:%s:%s", customerId, usageTime, "byOrgAndRepo")
	case ByCustomerRepoByProductSku:
		return fmt.Sprintf("%s:repo:%d:%s:%s", customerId, billingItem.EntityDetail.RepositoryId, usageTime, "byProductSku")
	case ByCustomerOrgByProductSku:
		return fmt.Sprintf("%s:org:%d:%s:%s", customerId, billingItem.EntityDetail.OrganizationId, usageTime, "byProductSku")
	case ByCustomerSku:
		return fmt.Sprintf("%s:%s:%s", customerId, billingItem.GetSku(), usageTime)
	case ByCustomerAzureEmission:
		return fmt.Sprintf("%s:%s", usageTime, "byAzureEmission")
	case ByCustomerZuoraEmission:
		currentTime := UTCNow().ToPartitionKey(t)
		return fmt.Sprintf("%s:%s", currentTime, "byZuoraEmission")
	case ByCustomerProduct:
		return fmt.Sprintf("%s:%s:%s", customerId, billingItem.GetProduct(), usageTime)
	case ByCustomerOrg:
		return fmt.Sprintf("%s:org:%d:%s", customerId, billingItem.EntityDetail.OrganizationId, usageTime)
	case ByCustomerRepo:
		return fmt.Sprintf("%s:repo:%d:%s", customerId, billingItem.EntityDetail.RepositoryId, usageTime)
	case ByOrgRepoProductSku:
		return fmt.Sprintf("customer:%s:org:%d:repo:%d:product:%s:sku:%s:%s", customerId, billingItem.EntityDetail.OrganizationId, billingItem.EntityDetail.RepositoryId, billingItem.GetProduct(), billingItem.GetSku(), usageTime)
	case ByCustomerOrgRepoProductSku:
		return fmt.Sprintf("%s:%s:%s", customerId, usageTime, "byOrgRepoProductSku")
	case ByCustomerAsEvent:
		return fmt.Sprintf("%s:%s:events", customerId, billingItem.GetSku())
	case ByCustomerAsEventRollup:
		return fmt.Sprintf("%s:%s:events:rollups", customerId, billingItem.GetSku())
	case MissingCustomer:
		return fmt.Sprintf("no-customer:%s", usageTime)
	default:
		return ""
	}
}

type UnitType byte

const (
	UnitTypeUnknown UnitType = iota
	UnitTypeSeconds
	UnitTypeMinutes // 1 minute = 60 seconds
	UnitTypeHours   // 1 hour = 3600 seconds
	UnitTypeBytes
	UnitTypeMegabytes      // 1 megabyte = 1024^2 bytes
	UnitTypeGigabytes      // 1 gigabyte = 1024^3 bytes
	UnitTypeByteHours      // 1 byte hour = 1 byte * 1 hour
	UnitTypeMegabyteHours  // 1 megabyte hour = 1024^2 bytehours
	UnitTypeGigabyteHours  // 1 gigabyte hour = 1024^3 bytehours
	UnitTypeGigabyteMonths // 1 gigabyte month = 1024^3 bytehours * 24 * 31
	UnitTypeUserMonths
)

func (b UnitType) ToProto() proto.UnitType {
	return proto.UnitType(b)
}

func (b UnitType) String() string {
	switch b {
	case UnitTypeUnknown:
		return ""
	case UnitTypeSeconds:
		return "seconds"
	case UnitTypeMinutes:
		return "minutes"
	case UnitTypeHours:
		return "hours"
	case UnitTypeBytes:
		return "bytes"
	case UnitTypeMegabytes:
		return "megabytes"
	case UnitTypeGigabytes:
		return "gigabytes"
	case UnitTypeByteHours:
		return "byte-hours"
	case UnitTypeMegabyteHours:
		return "megabyte-hours"
	case UnitTypeGigabyteHours:
		return "gigabyte-hours"
	case UnitTypeGigabyteMonths:
		return "gigabyte-months"
	case UnitTypeUserMonths:
		return "user-months"
	default:
		return fmt.Sprintf("%d", int(b))
	}
}
