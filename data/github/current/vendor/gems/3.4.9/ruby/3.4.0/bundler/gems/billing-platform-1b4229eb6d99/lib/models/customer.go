package models

import (
	"fmt"
	"strings"
	"time"

	"github.com/github/feature-management-client-go/vexi"
	vexi_extensions "github.com/github/feature-management-client-go/vexi/extensions"

	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
)

type CustomerId interface {
	GetCustomerId() string
}

type BillingTarget byte

const (
	NoBillingTarget BillingTarget = iota
	Zuora
	Azure
)

func (b BillingTarget) ToProto() proto.BillingTarget {
	return proto.BillingTarget(b)
}

type CanProceedStatus byte

const (
	UsageAllowed CanProceedStatus = iota
	BillingLocked
	FullTradeRestrictionsApplied
	AnyTradeRestrictionsApplied
	CommercialInteractionRestrictionApplied
	NotBillable
	BudgetLimitReached
	OnTrial
	ProductNotEnabled
)

func (s CanProceedStatus) ToProto() proto.CanProceedWithUsageStatus {
	return proto.CanProceedWithUsageStatus(s)
}

func GetRepoPartitionKey(pk string) string {
	return fmt.Sprintf("%s:byOrgAndRepo", pk)
}

// mostly a place holder will need lots more data to make customer work
type CostCenterDetail struct {
	EnterpriseCustomerId string
	CostCenterUUID       string
	IsCostCenterProxy    bool
	CostCenterState      CostCenterState
}

func (c CostCenterDetail) GetCustomerId() string {
	if c.IsCostCenterProxy {
		return c.CostCenterUUID
	}

	return c.EnterpriseCustomerId
}

type Customer struct {
	*Key
	*CostCenterDetail
	BillingTarget          BillingTarget
	AzureAccountId         string
	ZuoraAccountId         string
	ZuoraAccountNumber     string
	EnabledProducts        []string
	EffectiveAt            int64
	DiscountPlanName       string
	BillForPublicRepoUsage bool
	HasPaymentMethod       bool
	HasZuoraSubscription   bool
	IsBillingLocked        bool
	IsStaffOwned           bool
	TradeScreening         *TradeScreening
}

type TradeScreening struct {
	HasAnyTradeRestrictions                       bool
	HasFullTradeRestrictions                      bool
	FeaturesWithCommercialInteractionRestrictions []string
}

func IsBillable(customer *Customer, costCenterKey *CostCenterKey) bool {
	if (costCenterKey != nil) && (costCenterKey.TargetType == AzureSubscription) {
		return (len(costCenterKey.TargetId) > 0) || customer.IsBillableViaAzure()
	}

	return customer.IsBillable()
}

func (c *Customer) IsBillable() bool {
	return c.IsBillableViaAzure() || c.IsBillableViaZuora()
}

func (c *Customer) IsBillableViaZuora() bool {
	return c.HasZuoraAccountNumber() && c.HasZuoraSubscription && c.HasPaymentMethod && c.BillingTarget == Zuora
}

func (c *Customer) IsBillableViaAzure() bool {
	return c.HasAzureAccountId() && c.BillingTarget == Azure
}

func (c *Customer) HasFullTradeRestrictions() bool {
	if c.TradeScreening == nil {
		return false
	}
	return c.TradeScreening.HasFullTradeRestrictions
}

func (c *Customer) HasAnyTradeRestrictions() bool {
	if c.TradeScreening == nil {
		return false
	}
	return c.TradeScreening.HasAnyTradeRestrictions
}

func (c *Customer) HasProductEnabled(product string) bool {
	for _, p := range c.EnabledProducts {
		if p == product {
			return true
		}
	}
	return false
}

func (c *Customer) HasCommercialInteractionRestriction(product string) bool {
	if c.TradeScreening == nil {
		return false
	}

	// This is a check for the various commercial interaction restrictions that can be applied to a customer
	// The list of features being considered can be found here:
	// https://github.com/github/github/blob/master/packages/management_tools/app/models/account_screening_profile.rb#L117-L129
	for _, feature := range c.TradeScreening.FeaturesWithCommercialInteractionRestrictions {
		// Commercial interaction restriction exclusive for Copilot usage
		// Current feature restriction names are "copilot" and "copilot_vnext"
		if product == "copilot" && strings.Contains(feature, "copilot") {
			return true
		}

		// Commercial interaction restriction for billable features
		if feature == "cost_management" {
			return true
		}
	}
	return false
}

func (c *Customer) ForZuora() bool {
	return c.BillingTarget == Zuora
}

func (c *Customer) HasZuoraAccountNumber() bool {
	return c.ZuoraAccountNumber != ""
}

func (c *Customer) HasAzureAccountId() bool {
	return c.AzureAccountId != ""
}

func (c *Customer) HasEnabledProduct(product string) bool {
	for _, p := range c.EnabledProducts {
		if p == product {
			return true
		}
	}
	return false
}

func (c *Customer) GetCustomerId() string {
	return c.CostCenterDetail.GetCustomerId()
}

func (c *Customer) GetHydroBillingTarget() hydro_schemas_billingplatform_v1_entities.BillingTarget {
	switch c.BillingTarget {
	case Zuora:
		return hydro_schemas_billingplatform_v1_entities.BillingTarget_ZUORA
	case Azure:
		return hydro_schemas_billingplatform_v1_entities.BillingTarget_AZURE
	default:
		return hydro_schemas_billingplatform_v1_entities.BillingTarget_UNKNOWN_TARGET
	}
}

func (c *Customer) IsOnTrial() bool {
	return c.DiscountPlanName == EnterpriseTrial
}

func (c *Customer) VexiActor() vexi.Actor {
	return vexi_extensions.NewCustomActorType("Customer", c.GetCustomerId())
}

func NewCustomerFromCostCenter(costCenter *CostCenterKey) *Customer {
	if costCenter.TargetType == AzureSubscription {
		return NewCustomerFrom(costCenter.Customer.EnterpriseCustomerId, costCenter.UUID,
			true, Azure, costCenter.TargetId, "", "", "", false, 0, []string{}, false, false, false, false, &TradeScreening{}, CostCenterActive)
	}
	if costCenter.TargetType == ZuoraSubscription {
		return NewCustomerFrom(costCenter.Customer.EnterpriseCustomerId, costCenter.UUID,
			true, Zuora, "", "", costCenter.TargetId, "", false, 0, []string{}, false, false, false, false, &TradeScreening{}, CostCenterActive)
	}
	return NewCustomerFrom(costCenter.Customer.EnterpriseCustomerId, costCenter.UUID,
		true, NoBillingTarget, "", "", "", "", false, 0, []string{}, false, false, false, false, &TradeScreening{}, CostCenterActive)
}

func NewCustomerKey(customerId string) *Key {
	return &Key{
		PartitionKey: toPartitionKeyFrom(customerId),
		Id:           "customer",
	}
}

func NewCustomerFrom(customerId string, costCenterUUID string, isCostCenterProxy bool, billingTarget BillingTarget,
	azureAccountId string, zuoraAccountId string, zuoraAccountNumber string, discountPlanName string,
	billForPublicRepoUsage bool, effectiveAt int64, enabledProducts []string, hasPaymentMethod bool,
	hasZuoraSubscription bool, isBillingLocked bool, isStaffOwned bool, tradeScreening *TradeScreening, costCenterState CostCenterState) *Customer {
	id := customerId
	if isCostCenterProxy {
		id = costCenterUUID
	}
	return &Customer{
		Key: NewCustomerKey(id),
		CostCenterDetail: &CostCenterDetail{
			EnterpriseCustomerId: customerId,
			IsCostCenterProxy:    isCostCenterProxy,
			CostCenterUUID:       costCenterUUID,
			CostCenterState:      costCenterState,
		},
		BillingTarget:          billingTarget,
		AzureAccountId:         azureAccountId,
		ZuoraAccountId:         zuoraAccountId,
		ZuoraAccountNumber:     zuoraAccountNumber,
		EnabledProducts:        enabledProducts,
		EffectiveAt:            effectiveAt,
		DiscountPlanName:       discountPlanName,
		BillForPublicRepoUsage: billForPublicRepoUsage,
		HasPaymentMethod:       hasPaymentMethod,
		HasZuoraSubscription:   hasZuoraSubscription,
		IsBillingLocked:        isBillingLocked,
		IsStaffOwned:           isStaffOwned,
		TradeScreening:         NewTradeScreeningFrom(tradeScreening),
	}
}

func NewTradeScreeningFrom(tradeScreening *TradeScreening) *TradeScreening {
	if tradeScreening == nil {
		return &TradeScreening{
			HasAnyTradeRestrictions:                       false,
			HasFullTradeRestrictions:                      false,
			FeaturesWithCommercialInteractionRestrictions: []string{},
		}
	}
	return &TradeScreening{
		HasAnyTradeRestrictions:                       tradeScreening.HasAnyTradeRestrictions,
		HasFullTradeRestrictions:                      tradeScreening.HasFullTradeRestrictions,
		FeaturesWithCommercialInteractionRestrictions: tradeScreening.FeaturesWithCommercialInteractionRestrictions,
	}
}

func NewCustomerFromProto(customer *proto.Customer) *Customer {
	if (len(customer.EnabledProducts) > 0) && (customer.EffectiveAt == 0) {
		customer.EffectiveAt = time.Now().Unix()
	}
	return NewCustomerFrom(
		customer.CustomerId,
		customer.CostCenterUUID,
		customer.IsCostCenterProxy,
		BillingTarget(customer.BillingTarget),
		customer.AzureAccountId,
		customer.ZuoraAccountId,
		customer.ZuoraAccountNumber,
		customer.DiscountPlanName,
		customer.BillForPublicRepoUsage,
		customer.EffectiveAt,
		customer.EnabledProducts,
		customer.HasPaymentMethod,
		customer.HasZuoraSubscription,
		customer.IsBillingLocked,
		customer.IsStaffOwned,
		NewTradeScreeningFromProto(customer.TradeScreening),
		CostCenterActive,
	)
}

func NewTradeScreeningFromProto(tradeScreening *proto.TradeScreening) *TradeScreening {
	if tradeScreening == nil {
		return &TradeScreening{
			HasAnyTradeRestrictions:                       false,
			HasFullTradeRestrictions:                      false,
			FeaturesWithCommercialInteractionRestrictions: []string{},
		}
	}
	return &TradeScreening{
		HasAnyTradeRestrictions:                       tradeScreening.HasAnyTradeRestrictions,
		HasFullTradeRestrictions:                      tradeScreening.HasFullTradeRestrictions,
		FeaturesWithCommercialInteractionRestrictions: tradeScreening.FeaturesWithCommercialInteractionRestrictions,
	}
}

func NewCustomerBy(id int64) *Customer {
	return NewCustomer(fmt.Sprintf("%d", id))
}

func NewCustomer(id string) *Customer {
	return NewCustomerFrom(id, "", false, NoBillingTarget, "", "", "", "", false, 0, []string{}, false, false, false, false, &TradeScreening{}, CostCenterActive)
}

func (c *Customer) ToPartitionKey() string {
	return toPartitionKeyFrom(c.GetCustomerId())
}

func (c *Customer) ToDiscountsPartitionKey() string {
	return CustomerIdToDiscountsPartitionKey(c.GetCustomerId())
}

func (c *Customer) ToDiscountStatePartitionKey(uuid string, year, month int64) string {
	return fmt.Sprintf("%s:%s:%d:%d", c.ToDiscountsPartitionKey(), uuid, year, month)
}

func CustomerIdToDiscountsPartitionKey(customerId string) string {
	return fmt.Sprintf("%s:discounts", toPartitionKeyFrom(customerId))
}

func (c *Customer) ToBudgetsPartitionKey() string {
	return CustomerIdToBudgetsPartitionKey(c.GetCustomerId())
}
func CustomerIdToBudgetsPartitionKey(customerId string) string {
	return fmt.Sprintf("%s:budgets", toPartitionKeyFrom(customerId))
}

func (c *Customer) ToCostCentersPartitionKey() string {
	return CustomerIdToCostCentersPartitionKey(c.GetCustomerId())
}

func (c *Customer) ToCostCentersByTargetPartitionKey() string {
	return fmt.Sprintf("%s:byTarget", CustomerIdToCostCentersPartitionKey(c.GetCustomerId()))
}

func CustomerIdToCostCentersPartitionKey(customerId string) string {
	return fmt.Sprintf("%s:costCenters", toPartitionKeyFrom(customerId))
}

func (c *Customer) ToInvoicePartitionKey() string {
	return CustomerIdToInvoicePartitionKey(c.GetCustomerId())
}

func CustomerIdToInvoicePartitionKey(customerId string) string {
	return fmt.Sprintf("%s:invoices", toPartitionKeyFrom(customerId))
}

func (c *Customer) ToProto() *proto.Customer {
	return &proto.Customer{
		CustomerId:             c.GetCustomerId(),
		CostCenterUUID:         c.CostCenterUUID,
		IsCostCenterProxy:      c.IsCostCenterProxy,
		BillingTarget:          c.BillingTarget.ToProto(),
		AzureAccountId:         c.AzureAccountId,
		ZuoraAccountId:         c.ZuoraAccountId,
		EnterpriseCustomerId:   c.EnterpriseCustomerId,
		EnabledProducts:        c.EnabledProducts,
		EffectiveAt:            c.EffectiveAt,
		ZuoraAccountNumber:     c.ZuoraAccountNumber,
		DiscountPlanName:       c.DiscountPlanName,
		BillForPublicRepoUsage: c.BillForPublicRepoUsage,
		HasPaymentMethod:       c.HasPaymentMethod,
		HasZuoraSubscription:   c.HasZuoraSubscription,
		IsBillingLocked:        c.IsBillingLocked,
		IsStaffOwned:           c.IsStaffOwned,
		TradeScreening:         c.TradeScreening.ToProto(),
		CostCenterState:        c.CostCenterState.ToProto(),
	}
}

func (ts *TradeScreening) ToProto() *proto.TradeScreening {
	if ts == nil {
		return &proto.TradeScreening{
			HasAnyTradeRestrictions:                       false,
			HasFullTradeRestrictions:                      false,
			FeaturesWithCommercialInteractionRestrictions: []string{},
		}
	}
	return &proto.TradeScreening{
		HasAnyTradeRestrictions:                       ts.HasAnyTradeRestrictions,
		HasFullTradeRestrictions:                      ts.HasFullTradeRestrictions,
		FeaturesWithCommercialInteractionRestrictions: ts.FeaturesWithCommercialInteractionRestrictions,
	}
}

func toPartitionKeyFrom(customerId string) string {
	return fmt.Sprintf("customer:%s", customerId)
}

func (c *Customer) GetLoggerFields() []kvp.Field {
	fields := []kvp.Field{
		kvp.String("customerId", c.GetCustomerId()),
		kvp.String("enterpriseCustomerId", c.EnterpriseCustomerId),
		kvp.Int64("effectiveAt", c.EffectiveAt),
		kvp.Bool("isCostCenterProxy", c.IsCostCenterProxy),
		kvp.Any("billingTarget", c.BillingTarget),
	}

	if c.ZuoraAccountNumber != "" {
		fields = append(fields, kvp.String("zuoraAccountNumber", c.ZuoraAccountNumber))
	}
	if c.AzureAccountId != "" {
		fields = append(fields, kvp.String("azureAccountId", c.AzureAccountId))
	}
	return fields
}
