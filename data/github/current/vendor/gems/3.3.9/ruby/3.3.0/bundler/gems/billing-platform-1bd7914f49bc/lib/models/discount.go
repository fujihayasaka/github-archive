package models

import (
	"fmt"
	"sort"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/google/uuid"
)

const PublicRepo100PercentDiscountUUID = "9cdf0dca-1b19-11ee-be56-0242ac120002"

const (
	EnterpriseTrial string = "enterprise_trial"
)

type Discount struct {
	*DiscountKey
	Percentage   float64
	TargetAmount int64
	Targets      []*DiscountTarget
	StartDate    int64
	EndDate      int64
}

type DiscountKey struct {
	*Key
	Uuid       string
	CustomerId string
}

type DiscountState struct {
	*Key
	Customer       *Customer
	IsFullyApplied bool
	CurrentAmount  int64
	TargetAmount   int64
	Uuid           string
	*CosmosProperties
}

type DiscountTrackItem struct {
	*Key
	*Amounts
	AmountApplied int64
}

type DiscountTargetLookup struct {
	*Key
	Uuids []string
}

type DiscountType byte
type DiscountTargetType byte

type PlanDiscount struct {
	Uuid         string
	TargetAmount float64
	Targets      []string
	StartDate    int64
	EndDate      int64
}

const (
	NoDiscountType DiscountType = iota
	FreeForPublicReposDiscountType
	PlanDiscountType
	DollarDiscountType
	PercentageDiscountType
)

// All DiscountTargetTypes available
// These are ordered by priority first to last applied
// Changing the orders here will affect the order of discounts applied
// See DiscountTargetsFor
const (
	NoDiscountTarget DiscountTargetType = iota
	SkuDiscount
	ProductDiscount
	RepoDiscount
	OrgDiscount
	EnterpriseDiscount
)

// DiscountTargetsFor returns the list of DiscountTargetTypes that apply to the given item
// These are ordered by priority first to last applied
func DiscountTargetsFor(item *Item) []DiscountTargetType {
	discountTypes := []DiscountTargetType{
		SkuDiscount,
		ProductDiscount,
		EnterpriseDiscount,
	}

	if item.GetOrgId() != 0 {
		discountTypes = append(discountTypes, OrgDiscount)
	}

	if item.GetRepoId() != 0 {
		discountTypes = append(discountTypes, RepoDiscount)
	}

	sort.Slice(discountTypes, func(i, j int) bool {
		return discountTypes[i] < discountTypes[j]
	})

	return discountTypes
}

type DiscountTarget struct {
	Id   string
	Type DiscountTargetType
}

func (t DiscountTargetType) ToProto() proto.DiscountTargetType {
	switch t {
	case SkuDiscount:
		return proto.DiscountTargetType_SkuDiscount
	case ProductDiscount:
		return proto.DiscountTargetType_ProductDiscount
	case RepoDiscount:
		return proto.DiscountTargetType_RepoDiscount
	case OrgDiscount:
		return proto.DiscountTargetType_OrgDiscount
	case EnterpriseDiscount:
		return proto.DiscountTargetType_EnterpriseDiscount
	default:
		return proto.DiscountTargetType_NoDiscountTarget
	}
}

func (t DiscountTargetType) String() string {
	switch t {
	case SkuDiscount:
		return "sku"
	case ProductDiscount:
		return "product"
	case RepoDiscount:
		return "repository"
	case OrgDiscount:
		return "organization"
	case EnterpriseDiscount:
		return "enterprise"
	default:
		return fmt.Sprintf("%d", int(t))
	}
}

func (t DiscountTargetType) GetTargetIdByTargetType(item *Item) string {
	switch t {
	case SkuDiscount:
		return item.GetSku()
	case ProductDiscount:
		return item.GetProduct()
	case RepoDiscount:
		repoId := item.GetRepoId()
		if repoId != 0 {
			return fmt.Sprintf("%d", repoId)
		} else {
			return ""
		}
	case OrgDiscount:
		orgId := item.GetOrgId()
		if orgId != 0 {
			return fmt.Sprintf("%d", orgId)
		} else {
			return ""
		}
	case EnterpriseDiscount:
		return item.EntityDetail.EnterpriseId()
	default:
		return ""
	}
}

func NewDiscountTrackItem(item *Item, discountState *DiscountState, discountAmount int64) *DiscountTrackItem {
	return &DiscountTrackItem{
		Key: &Key{
			Id:           item.PartitionKey,
			PartitionKey: discountState.PartitionKey,
		},
		Amounts:       item.Amounts,
		AmountApplied: discountAmount,
	}
}

func NewDiscountTrackItemFromDiscount(item *Item, discountKey *DiscountKey, discountAmount int64, year int64, month int64) *DiscountTrackItem {
	customer := NewCustomer(discountKey.CustomerId)

	return &DiscountTrackItem{
		Key: &Key{
			Id:           item.PartitionKey,
			PartitionKey: customer.ToDiscountStatePartitionKey(discountKey.Uuid, year, month),
		},
		Amounts:       item.Amounts,
		AmountApplied: discountAmount,
	}
}

func NewDiscountTargetWith(id string, t DiscountTargetType) *DiscountTarget {
	return &DiscountTarget{
		Id:   id,
		Type: t,
	}
}

func NewDiscountTarget(discountTarget *proto.DiscountTarget) *DiscountTarget {
	return NewDiscountTargetWith(discountTarget.Id, ToDiscountTargetType(discountTarget.Type))
}

func ToDiscountTargetType(t proto.DiscountTargetType) DiscountTargetType {
	return DiscountTargetType(t)
}

func NewDiscount(customerId string, targetsProto []*proto.DiscountTarget, percentage float64, targetAmount float64, startDate, endDate int64) *Discount {
	customer := NewCustomer(customerId)
	uuid := uuid.New().String()

	targets := make([]*DiscountTarget, len(targetsProto))
	for i, t := range targetsProto {
		targets[i] = NewDiscountTarget(t)
	}

	return &Discount{
		DiscountKey:  NewDiscountKey(customer, uuid),
		Targets:      targets,
		TargetAmount: ToWholeAmount[int64](targetAmount),
		Percentage:   percentage,
		StartDate:    startDate,
		EndDate:      endDate,
	}
}

func NewPlanDiscountForSku(planDiscount *PlanDiscount) *Discount {
	discountTargets := make([]*DiscountTarget, 0)
	for _, target := range planDiscount.Targets {
		discountTargets = append(discountTargets, &DiscountTarget{
			Id:   target,
			Type: SkuDiscount,
		})
	}

	return &Discount{
		DiscountKey:  NewPlanDiscountKey(planDiscount.Uuid),
		Targets:      discountTargets,
		TargetAmount: ToWholeAmount[int64](planDiscount.TargetAmount),
		Percentage:   0,
		StartDate:    planDiscount.StartDate,
		EndDate:      planDiscount.EndDate,
	}
}

func NewPlanDiscountKey(uuid string) *DiscountKey {
	return &DiscountKey{
		Key: &Key{
			PartitionKey: "discounts",
			Id:           uuid,
		},
		Uuid: uuid,
	}
}

// we need a static UUID for 100% discounts so we can track their state
func New100PercentDiscountForSku(customerId string, sku string, now *UsageTime) *Discount {
	return &Discount{
		DiscountKey: NewDiscountKey(NewCustomer(customerId), PublicRepo100PercentDiscountUUID),
		Targets: []*DiscountTarget{
			{Id: sku, Type: SkuDiscount},
		},
		TargetAmount: 0,
		Percentage:   100.0,
		StartDate:    now.AddDate(-1, 0, 0).Unix(),
		EndDate:      now.AddDate(1, 0, 0).Unix(),
	}
}

func NewDiscountKey(customer *Customer, uuid string) *DiscountKey {
	return &DiscountKey{
		Key: &Key{
			PartitionKey: customer.ToDiscountsPartitionKey(),
			Id:           uuid,
		},
		Uuid:       uuid,
		CustomerId: customer.GetCustomerId(),
	}
}

func NewDiscountKeyFromProto(key *proto.DiscountKey) *DiscountKey {
	customer := NewCustomer(key.CustomerId)
	return NewDiscountKey(customer, key.Uuid)
}

func (dk *DiscountKey) ToDiscountStateKey(year, month int64) *Key {
	return &Key{
		PartitionKey: fmt.Sprintf("%s:%s:%d:%d", dk.PartitionKey, dk.Id, year, month),
		Id:           "discountState",
	}
}

func NewDiscountState(customerId string, discountKey *DiscountKey, discount *Discount, year, month int64) *DiscountState {
	customer := NewCustomer(customerId)

	return &DiscountState{
		Key:            discountKey.ToDiscountStateKey(year, month),
		Customer:       customer,
		IsFullyApplied: false,
		CurrentAmount:  0,
		TargetAmount:   discount.TargetAmount,
		Uuid:           discount.Uuid,
	}
}

func NewDiscountStateKey(customer *Customer, uuid string, year, month int64) *Key {
	return &Key{
		PartitionKey: customer.ToDiscountStatePartitionKey(uuid, year, month),
		Id:           "discountState",
	}
}

func ToTargetLookupKey(customerDiscountsPartitionKey string, target *DiscountTarget) *Key {
	return &Key{
		PartitionKey: customerDiscountsPartitionKey,
		Id:           fmt.Sprintf("%s:%s:%s", "targetLookup", target.Type, target.Id),
	}
}

func (d *Discount) AsTargetLookup(target *DiscountTarget) *DiscountTargetLookup {
	return &DiscountTargetLookup{
		Key:   ToTargetLookupKey(d.PartitionKey, target),
		Uuids: []string{d.Uuid},
	}
}

func (d *Discount) ToProto() *proto.Discount {
	targetsProto := make([]*proto.DiscountTarget, 0)
	for _, target := range d.Targets {
		targetsProto = append(targetsProto, &proto.DiscountTarget{
			Id:   target.Id,
			Type: target.Type.ToProto(),
		})
	}

	return &proto.Discount{
		CustomerId:   d.CustomerId,
		Percentage:   d.Percentage,
		TargetAmount: ToDecimalAmount(d.TargetAmount),
		Targets:      targetsProto,
		Uuid:         d.Uuid,
		StartDate:    d.StartDate,
		EndDate:      d.EndDate,
	}
}

func (d *Discount) IsPercentage() bool {
	return d.Percentage != 0
}

func (d *Discount) IsDollar() bool {
	return d.TargetAmount != 0
}

func (d *Discount) IsValidFor(date *UsageTime) bool {
	unixTimestamp := date.Unix()
	return (d.StartDate <= unixTimestamp) && (d.EndDate >= unixTimestamp)
}

type DiscountItem struct {
	*Key
	DiscountAmount int64
	Quantity       int64
	Pricing        *Pricing
	UsageAt        UsageTime
	DiscountFor    *Discount
}

func GetDiscountPartitionKey(pk string) string {
	return fmt.Sprintf("%s:discount", pk)
}

func (di *DiscountItem) asBillingItem() *Item {
	return &Item{
		Pricing: di.Pricing,
	}
}

func (di *DiscountItem) GetPartitionKey(t ActiveType, upt UsagePartitionType) string {
	item := di.asBillingItem()
	return GetPartitionKey(item, upt, t)
}

func (billingItem *Item) AsCurrentItemWithDiscountKey() *Item {
	copy := *billingItem
	copy.PartitionKey = GetDiscountPartitionKey(billingItem.PartitionKey)
	return &copy
}

func (billingItem *Item) DiscountItemKey(t ActiveType, upt UsagePartitionType) *Key {
	return &Key{
		Id:           billingItem.PartitionKey,
		PartitionKey: GetDiscountPartitionKey(billingItem.GetPartitionKey(t, upt)),
	}
}

func (discountItem *DiscountItem) AsDiscountItemWithIdAndPartitionKeyOfType(item *Item, from ActiveType, to ActiveType, upt UsagePartitionType) *DiscountItem {
	copy := *discountItem
	copy.Id = GetDiscountPartitionKey(item.GetPartitionKey(from, ByCustomerSku))
	copy.PartitionKey = GetDiscountPartitionKey(item.GetPartitionKey(to, upt))
	return &copy
}

func (discountItem *DiscountItem) AsDiscountItemWithIdAndPartitionKeyForByCustomerOrgRepoProductSku(item *Item, from ActiveType, to ActiveType) *DiscountItem {
	copy := *discountItem
	// we set a different ID partition type than the PK type because we want the items to be unique per org, repo, product SKU which
	// ByOrgRepoProductSku is.
	copy.Id = item.GetPartitionKey(from, ByOrgRepoProductSku)
	copy.PartitionKey = GetDiscountPartitionKey(item.GetPartitionKey(to, ByCustomerOrgRepoProductSku))
	return &copy
}

func (discountItem *DiscountItem) GetSku() string {
	if discountItem.Pricing != nil {
		return discountItem.Pricing.Sku
	}

	return ""
}

func (discountItem *DiscountItem) GetProduct() string {
	if discountItem.Pricing != nil {
		return discountItem.Pricing.Product
	}

	return ""
}

func (amounts Amounts) AmountsWithDiscountApplied(discountItem *DiscountItem) *Amounts {
	if discountItem == nil {
		return &amounts
	}

	quantityAfterDiscount := amounts.Quantity - discountItem.Quantity
	amountAfterDiscount := amounts.BilledAmount - discountItem.DiscountAmount

	amountsWithDiscountApplied := &Amounts{
		FullQuantity: amounts.FullQuantity,
		Quantity:     quantityAfterDiscount,
		BilledAmount: amountAfterDiscount,
	}
	return amountsWithDiscountApplied.EnsureNonNegative()
}

func (d *Discount) CalculatePercentageDiscountAmount(billedAmount int64) int64 {
	discountAmount := (ToDecimalAmount(billedAmount) * d.Percentage) / 100
	return ToWholeAmount[int64](discountAmount)
}

func (ds *DiscountState) ToProto() *proto.DiscountState {
	return &proto.DiscountState{
		IsFullyApplied: ds.IsFullyApplied,
		CurrentAmount:  ToDecimalAmount(ds.CurrentAmount),
	}
}

func (ds *DiscountState) IsNewDocument() bool {
	return ds.CosmosProperties == nil
}

func ToProtoDiscountState(isFullyApplied bool, currentAmount, targetAmount int64, percentage float64, uuid string, targets []*DiscountTarget) *proto.DiscountState {
	targetsProto := make([]*proto.DiscountTarget, 0)
	for _, target := range targets {
		targetsProto = append(targetsProto, &proto.DiscountTarget{
			Id:   target.Id,
			Type: target.Type.ToProto(),
		})
	}
	return &proto.DiscountState{
		IsFullyApplied: isFullyApplied,
		CurrentAmount:  ToDecimalAmount(currentAmount),
		TargetAmount:   ToDecimalAmount(targetAmount),
		Percentage:     percentage,
		Uuid:           uuid,
		Targets:        targetsProto,
	}
}

func (billingItem *Item) AsDiscountItemWithAmount(amountAfterDiscounts int64) *DiscountItem {
	if amountAfterDiscounts == 0 {
		return &DiscountItem{
			Key:            billingItem.DiscountItemKey(Hourly, ByCustomerSku),
			Pricing:        billingItem.Pricing,
			Quantity:       billingItem.Quantity,
			DiscountAmount: billingItem.BilledAmount,
			UsageAt:        billingItem.UsageAt,
		}
	}

	nanoAmountAfterDiscounts := nano.NewFromInt(amountAfterDiscounts)
	nanoBilledAmount := nano.NewFromInt(billingItem.BilledAmount)
	nanoDiscountAmount := nanoBilledAmount.Sub(nanoAmountAfterDiscounts)
	nanoAppliedCostPerQuantity := nano.NewFromInt(billingItem.AppliedCostPerQuantity)

	nanoDiscountQuantity := nanoDiscountAmount.Div(nanoAppliedCostPerQuantity)

	return &DiscountItem{
		Key:            billingItem.DiscountItemKey(Hourly, ByCustomerSku),
		Pricing:        billingItem.Pricing,
		Quantity:       nanoDiscountQuantity.Int64(),
		DiscountAmount: nanoDiscountAmount.Int64(),
		UsageAt:        billingItem.UsageAt,
	}
}

func (discountItem *DiscountItem) AsHourlyDiscountItemByCustomerFrom(item *Item) *DiscountItem {
	copy := discountItem

	copy.Id = item.PartitionKey
	copy.PartitionKey = GetDiscountPartitionKey(item.GetPartitionKey(Hourly, ByCustomer))

	return copy
}

func (discountItem *DiscountItem) AsHourlyDiscountItemByCustomerOrgRepoProductSkuFrom(item *Item) *DiscountItem {
	copy := discountItem

	// setting the discount items id to be the partition key of the input hourly item
	// allows us to later track these hourly discount items to the usage line item they are associated with.
	copy.Id = item.PartitionKey
	copy.PartitionKey = GetDiscountPartitionKey(item.GetPartitionKey(Hourly, ByCustomerOrgRepoProductSku))

	return copy
}

func (discountItem *DiscountItem) ToProto() *proto.DiscountItem {

	var selfReference *proto.Key
	if discountItem.Id != "" || discountItem.PartitionKey != "" {
		selfReference = &proto.Key{
			PartitionKey: discountItem.PartitionKey,
			Id:           discountItem.Id,
		}
	}

	return &proto.DiscountItem{
		DiscountAmount: ToDecimalAmount(discountItem.DiscountAmount),
		Quantity:       ToDecimalAmount(discountItem.Quantity),
		Sku:            discountItem.Pricing.Sku,
		Product:        discountItem.Pricing.Product,
		SelfReference:  selfReference,
		UsageAt:        discountItem.UsageAt.UnixMilli(),
		UnitType:       discountItem.asBillingItem().GetUnitType().ToProto(),
	}
}

func (discount *Discount) AsDollarValue(billedAmount int64, currentAmount int64) int64 {
	if discount.IsPercentage() {
		return discount.CalculatePercentageDiscountAmount(billedAmount)
	}

	return discount.TargetAmount - currentAmount
}
