package models

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/google/uuid"
)

// Budget

type Budget struct {
	*BudgetKey
	Uuid            string
	TargetAmount    uint64
	BudgetLimitType BudgetLimitType
	*BudgetAlerting
}

func NewBudget(input *proto.Budget) (*Budget, error) {
	return &Budget{
		BudgetKey:       NewBudgetKey(input.Key),
		TargetAmount:    ToWholeAmount[uint64](input.TargetAmount),
		BudgetLimitType: ToBudgetLimitType(input.BudgetLimitType),
		BudgetAlerting:  NewBudgetAlerting(input.BudgetAlerting),
		Uuid:            uuid.New().String(),
	}, nil
}

func (b *Budget) ToProto() *proto.Budget {
	return &proto.Budget{
		TargetAmount:    ToDecimalAmount(b.TargetAmount),
		Key:             b.BudgetKey.ToProto(),
		BudgetLimitType: b.BudgetLimitType.ToProto(),
		BudgetAlerting:  b.BudgetAlerting.ToProto(),
		Uuid:            b.Uuid,
	}
}

// Budget Limit Type

type BudgetLimitType byte

const (
	IgnoreLimit BudgetLimitType = iota
	AlertingOnly
	PreventFurtherUsage
	StopActiveUsage
)

func ToBudgetLimitType(t proto.BudgetLimitType) BudgetLimitType {
	return BudgetLimitType(t)
}

func (b BudgetLimitType) ToProto() proto.BudgetLimitType {
	return proto.BudgetLimitType(b)
}

func (b BudgetLimitType) String() string {
	switch b {
	case AlertingOnly:
		return "alerting_only"
	case PreventFurtherUsage:
		return "prevent_further_usage"
	case StopActiveUsage:
		return "stop_active_usage"
	default:
		return fmt.Sprintf("%d", int(b))
	}
}

func (b BudgetLimitType) softLimit() bool {
	return b == AlertingOnly || b == IgnoreLimit
}

func (b BudgetLimitType) HardLimit() bool {
	return b == PreventFurtherUsage || b == StopActiveUsage
}

// Pricing Target Type

type PricingTargetType byte

const (
	NoPricingTarget PricingTargetType = iota
	ProductPricing
	SkuPricing
)

func ToPricingTargetType(t proto.PricingTargetType) PricingTargetType {
	return PricingTargetType(t)
}

func (p PricingTargetType) ToProto() proto.PricingTargetType {
	return proto.PricingTargetType(p)
}

func (p PricingTargetType) String() string {
	switch p {
	case ProductPricing:
		return "product"
	case SkuPricing:
		return "sku"
	default:
		return fmt.Sprintf("%d", int(p))
	}
}

// Budget Key

type BudgetKey struct {
	*Key
	customerPartitionKey string
	CustomerId           string
	TargetId             string
	TargetType           ResourceType
	PricingTargetType    PricingTargetType
	PricingTargetId      string
}

func NewBudgetKey(input *proto.BudgetKey) *BudgetKey {
	targetType := ToResourceType(input.TargetType)
	pricingTargetType := ToPricingTargetType(input.PricingTargetType)

	return NewBudgetKeyFromParts(
		input.CustomerId,
		targetType,
		input.TargetId,
		pricingTargetType,
		input.PricingTargetId,
	)
}

func NewBudgetKeyFromCustomer(customerId string,
	targetType ResourceType,
	targetId string,
	pricingTargetType PricingTargetType,
	pricingTargetId string,
) *BudgetKey {
	customerPartitionKey := CustomerIdToBudgetsPartitionKey(customerId)
	key := &BudgetKey{
		customerPartitionKey: customerPartitionKey,
		Key: &Key{
			PartitionKey: customerPartitionKey,
		},
		CustomerId:        customerId,
		TargetId:          targetId,
		TargetType:        targetType,
		PricingTargetType: pricingTargetType,
		PricingTargetId:   pricingTargetId,
	}
	key.Id = key.getSpecificBudgetSourceId(targetType)

	return key
}

func NewBudgetKeyFromExistingKey(customerId string, budgetKey *BudgetKey) *BudgetKey {
	if budgetKey.TargetType == CustomerResource {
		return NewBudgetKeyFromParts(
			customerId,
			budgetKey.TargetType,
			customerId,
			budgetKey.PricingTargetType,
			budgetKey.PricingTargetId,
		)
	}

	return NewBudgetKeyFromParts(
		customerId,
		budgetKey.TargetType,
		budgetKey.TargetId,
		budgetKey.PricingTargetType,
		budgetKey.PricingTargetId,
	)
}

func NewBudgetKeyFromParts(customerId string,
	targetType ResourceType,
	targetId string,
	pricingTargetType PricingTargetType,
	pricingTargetId string,
) *BudgetKey {
	return NewBudgetKeyFromCustomer(
		customerId,
		targetType,
		targetId,
		pricingTargetType,
		pricingTargetId,
	)
}

func (b *BudgetKey) ToPartitionKeyAsForResourceType(targetType *ResourceType) *Key {
	return &Key{
		PartitionKey: b.PartitionKey,
		Id:           b.getSpecificBudgetSourceId(*targetType),
	}
}

func (b *BudgetKey) ToPartitionKey(year, month int64) string {
	return fmt.Sprintf("%s:%d:%d", b.Id, year, month)
}

func (b *BudgetKey) getSpecificBudgetSourceId(targetType ResourceType) string {
	pricingTypeFormat := ""
	if b.PricingTargetType != NoPricingTarget {
		pricingTypeFormat = fmt.Sprintf(":%s:%s",
			b.PricingTargetType,
			b.PricingTargetId,
		)
	}

	return fmt.Sprintf("%s:%s:%s%s",
		b.customerPartitionKey,
		targetType,
		b.TargetId,
		pricingTypeFormat,
	)
}

func (b *BudgetKey) String() string {
	return fmt.Sprintf("BudgetKey{PartitionKey: %s, CustomerId: %s, TargetId: %s, TargetType: %s, PricingTargetType: %s, PricingTargetId: %s}",
		b.customerPartitionKey, b.CustomerId, b.TargetId, b.TargetType, b.PricingTargetType, b.PricingTargetId)
}

func (b *BudgetKey) ToProto() *proto.BudgetKey {
	return &proto.BudgetKey{
		CustomerId:        b.CustomerId,
		TargetType:        b.TargetType.ToProto(),
		TargetId:          b.TargetId,
		PricingTargetType: proto.PricingTargetType(b.PricingTargetType),
		PricingTargetId:   b.PricingTargetId,
	}
}

func (b *BudgetKey) ToBudgetStateKey(year, month int64, id string) *Key {
	partitionKey := b.ToPartitionKey(year, month)
	return &Key{
		PartitionKey: partitionKey,
		Id:           id,
	}
}

// Budget Threshold

type BudgetThreshold struct {
	Name                   string
	MinimumUsagePercentage uint64
	Alertable              bool
}

func (b *BudgetThreshold) ToProto() *proto.BudgetThreshold {
	return &proto.BudgetThreshold{
		Name:                   b.Name,
		MinimumUsagePercentage: float64(b.MinimumUsagePercentage),
		Alertable:              b.Alertable,
	}
}

func BudgetThresholds() []BudgetThreshold {
	thresholds := []BudgetThreshold{
		// {Name: "100%", MinimumUsagePercentage: ToWholeAmount[uint64](1.0), Alertable: true},
		// {Name: "90%", MinimumUsagePercentage: ToWholeAmount[uint64](0.9), Alertable: true},
		// {Name: "75%", MinimumUsagePercentage: ToWholeAmount[uint64](0.75), Alertable: true},
		{Name: "100%", MinimumUsagePercentage: 100, Alertable: true},
		{Name: "90%", MinimumUsagePercentage: 90, Alertable: true},
		{Name: "75%", MinimumUsagePercentage: 75, Alertable: true},
	}

	// ensure that thresholds are sorted from most to least usage
	sort.Slice(thresholds, func(i, j int) bool {
		return thresholds[i].MinimumUsagePercentage > thresholds[j].MinimumUsagePercentage
	})

	return thresholds
}

func (b *BudgetState) GetThresholdMet() *BudgetThreshold {
	// uggg floats
	currentUsagePercentage := uint64((float64(b.CurrentAmount) / float64(b.TargetAmount)) * 100)
	thresholds := BudgetThresholds()

	for _, t := range thresholds {
		if currentUsagePercentage >= t.MinimumUsagePercentage {
			return &t
		}
	}

	return &BudgetThreshold{
		Name:                   "No threshold met",
		MinimumUsagePercentage: 0,
		Alertable:              false,
	}
}

func (b *BudgetState) String() string {
	return fmt.Sprintf("BudgetState{Key: %v, CurrentAmount: %d, Quantity: %d, IsFullyFunded: %t, TargetAmount: %d, ThresholdMet: %v}",
		b.Key, b.CurrentAmount, b.Quantity, b.IsFullyFunded, b.TargetAmount, b.ThresholdMet)
}

// Budget State

type BudgetState struct {
	*Key
	CurrentAmount uint64
	Quantity      int64
	IsFullyFunded bool
	TargetAmount  uint64
	ThresholdMet  BudgetThreshold
	ETag          *azcore.ETag `json:"_etag"`
}

func NewBudgetState(budget *Budget, year, month int64) *BudgetState {
	return &BudgetState{
		Key: &Key{
			PartitionKey: budget.ToPartitionKey(year, month),
			Id:           "budgetState",
		},
		Quantity:      0,
		CurrentAmount: 0,
		TargetAmount:  budget.TargetAmount,
		IsFullyFunded: false,
	}
}

func NewBudgetStateFromExistingBudgetState(budget *Budget, budgetState *BudgetState) (*BudgetState, error) {
	keyParts := strings.Split(budgetState.PartitionKey, ":")
	year, err := strconv.ParseInt(keyParts[len(keyParts)-2], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid year: %v", err)
	}
	month, err := strconv.ParseInt(keyParts[len(keyParts)-1], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid month: %v", err)
	}
	key := &Key{
		PartitionKey: budget.ToPartitionKey(year, month),
		Id:           "budgetState",
	}
	return &BudgetState{
		Key:           key,
		Quantity:      budgetState.Quantity,
		CurrentAmount: budgetState.CurrentAmount,
		TargetAmount:  budgetState.TargetAmount,
		IsFullyFunded: budgetState.IsFullyFunded,
	}, nil
}

func (b *BudgetState) ToProto() *proto.BudgetState {
	return &proto.BudgetState{
		IsFullyFunded: b.IsFullyFunded,
		CurrentAmount: ToDecimalAmount(b.CurrentAmount),
		Quantity:      ToDecimalAmount(b.Quantity),
		TargetAmount:  ToDecimalAmount(b.TargetAmount),
		ThresholdMet:  b.ThresholdMet.ToProto(),
	}
}

func (budgetState BudgetState) CalculateOverage(budget Budget, additionalAmount int64) int64 {
	if budget.BudgetLimitType.softLimit() {
		return 0
	}

	overageAmount := (int64(budgetState.CurrentAmount) + additionalAmount) - int64(budgetState.TargetAmount)
	if overageAmount < 0 {
		overageAmount = 0
	}

	return overageAmount
}

func MaxOverageAmount(overageAmounts []int64) int64 {
	max := int64(0)
	for _, amount := range overageAmounts {
		if amount > max {
			max = amount
		}
	}

	return max
}

// Budget Info

type BudgetInfo struct {
	*Budget
	*BudgetState
}

func (b *BudgetInfo) ToProto() *proto.BudgetInfo {
	return &proto.BudgetInfo{
		Budget:      b.Budget.ToProto(),
		BudgetState: b.BudgetState.ToProto(),
	}
}

// Budget Alerting

type BudgetAlerting struct {
	WillAlert        bool
	RecipientUserIDs []string
}

func NewBudgetAlerting(input *proto.BudgetAlerting) *BudgetAlerting {
	return &BudgetAlerting{
		WillAlert:        input.WillAlert,
		RecipientUserIDs: input.RecipientUserIds,
	}
}

func (b *BudgetAlerting) ToProto() *proto.BudgetAlerting {
	return &proto.BudgetAlerting{
		WillAlert:        b.WillAlert,
		RecipientUserIds: b.RecipientUserIDs,
	}
}

// Budget Amount Item

type BudgetAmountItem struct {
	AmountsItem
	TargetAmount uint64
}

type BudgetStateUpdateJob struct {
	Budget *Budget
	Year   int64
	Month  int64
	Sku    string
	Amount *Amounts
}

func NewBudgetStateJob(budget *Budget, year int64, month int64, sku string, amount *Amounts) *BudgetStateUpdateJob {
	return &BudgetStateUpdateJob{
		Budget: budget,
		Year:   year,
		Month:  month,
		Sku:    sku,
		Amount: amount,
	}
}
