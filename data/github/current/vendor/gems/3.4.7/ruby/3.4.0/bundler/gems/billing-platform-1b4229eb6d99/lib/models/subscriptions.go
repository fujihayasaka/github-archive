package models

import (
	"fmt"

	"github.com/github/billing-platform/lib/twirp/proto"
)

type SubscriptionStatus byte

const (
	SubscriptionActive SubscriptionStatus = iota
	SubscriptionInactive
)

func ToSubscriptionStatus(t proto.SubscriptionStatus) SubscriptionStatus {
	return SubscriptionStatus(t)
}

func (b SubscriptionStatus) ToProto() proto.SubscriptionStatus {
	return proto.SubscriptionStatus(b)
}

func (b SubscriptionStatus) String() string {
	switch b {
	case SubscriptionActive:
		return "active"
	case SubscriptionInactive:
		return "inactive"
	default:
		return fmt.Sprintf("%d", int(b))
	}
}

func (b SubscriptionStatus) ToPrimaryKey() string {
	switch b {
	case SubscriptionActive:
		return "license_add"
	case SubscriptionInactive:
		return "license_remove"
	default:
		return "license_unknown"
	}
}

func (b SubscriptionStatus) ToQuantity() float64 {
	switch b {
	case SubscriptionActive:
		return 1.0
	case SubscriptionInactive:
		return -1.0
	default:
		return 0.0
	}
}

type SubscriptionTotal struct {
	AmountsItem
}

type SubscribedItem struct {
	Key
	Sku            string `json:"sku"`
	SubscriptionId int64  `json:"subscription_id"`
	CosmosProperties
	SubscriptionStatus    SubscriptionStatus `json:"subscription_status"`
	LastBilledAt          *UsageTime         `json:"last_billed_at"`
	LicenseSubscriptionAt *UsageTime         `json:"license_subscription_at"`
	EntityDetail          *EntityDetail      `json:"entity_detail"`
	UpdatedAt             *UsageTime         `json:"updated_at"`
}

func NewSubscribedItemFromItem(item *Item) *SubscribedItem {
	status := SubscriptionActive
	if item.Quantity < 1 {
		status = SubscriptionInactive
	}
	return &SubscribedItem{
		Key:                   toSubscribedItemkey(item.EntityDetail, item.GetSku()),
		SubscriptionId:        item.EntityDetail.ActorId,
		Sku:                   item.GetSku(),
		SubscriptionStatus:    status,
		LicenseSubscriptionAt: &item.UsageAt,
		EntityDetail:          item.EntityDetail,
		UpdatedAt:             &item.UsageAt,
	}
}

func NewSubscribedItem(req *proto.LicenseRequest, status SubscriptionStatus) *SubscribedItem {
	entityDetail := req.EntityDetail
	return &SubscribedItem{
		Key:                   toSubscribedItemkey(NewEntityDetail(entityDetail), req.Sku),
		Sku:                   req.Sku,
		SubscriptionId:        req.EntityDetail.ActorId,
		SubscriptionStatus:    status,
		LicenseSubscriptionAt: NewUsageTimeFromProto(req.SubscriptionAt),
		EntityDetail: &EntityDetail{
			CustomerId:       entityDetail.CustomerId,
			OrganizationId:   entityDetail.OwnerId,
			RepositoryId:     entityDetail.RepoId,
			ActorId:          entityDetail.ActorId,
			CostCenterDetail: &CostCenterDetail{},
		},
		UpdatedAt: NewUsageTimeFromProto(req.SubscriptionAt),
	}
}

func NewSubscribedItemKey(customerId string, sku string, actorId int64) Key {
	return toSubscribedItemkey(&EntityDetail{CustomerId: customerId, ActorId: actorId}, sku)
}

func toSubscribedItemkey(entity *EntityDetail, sku string) Key {
	return Key{
		PartitionKey: ToSubscriptionMgmtPartitionKey(entity.CustomerId, sku),
		Id:           fmt.Sprintf("subscription:%d", entity.ActorId),
	}
}

func ToSubscriptionPartitionKeyForGivenMonthHighWaterMark(customerId string, sku string, usageAt UsageTime) *Key {
	usageTime := usageAt.ToPartitionKey(Monthly)
	key := ToSubscriptionPartitionKeyActualCurrentTotal(customerId, sku)
	key.Id = fmt.Sprintf("%s:%s", key.Id, usageTime)
	key.PartitionKey = fmt.Sprintf("%s:%s", key.PartitionKey, usageTime)

	return key
}

func ToSubscriptionPartitionKeyActualCurrentTotal(customerId string, sku string) *Key {
	value := ToSubscriptionMgmtPartitionKey(customerId, sku)
	return &Key{
		Id:           value,
		PartitionKey: value,
	}
}

func ToSubscriptionMgmtPartitionKey(customerId string, sku string) string {
	return fmt.Sprintf("%s:highWatermark:%s", customerId, sku)
}

func (s *SubscribedItem) ToProto() *proto.SubscribedItem {
	if s == nil {
		return nil
	}

	var lastBilledAt int64 = 0
	if s.LastBilledAt != nil {
		lastBilledAt = s.LastBilledAt.UnixMilli()
	}

	var licenseSubscriptionAt int64 = 0
	if s.LicenseSubscriptionAt != nil {
		licenseSubscriptionAt = s.LicenseSubscriptionAt.UnixMilli()
	}
	return &proto.SubscribedItem{
		SubscriptionId:  s.SubscriptionId,
		Status:          s.SubscriptionStatus.ToProto(),
		SubscribedAt:    licenseSubscriptionAt,
		LastBilledForAt: lastBilledAt,
	}
}
