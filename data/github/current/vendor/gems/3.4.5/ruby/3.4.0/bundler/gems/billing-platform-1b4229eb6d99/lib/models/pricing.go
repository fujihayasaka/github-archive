package models

import (
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/twirp/proto"
)

type PricingMeterType byte

const (
	PricingMeterDefault           = iota // aka DirectSummation, aka actions minutes. defaulting to zero instead of unknown so that will backfill any existing data by default
	PricingMeterPerHourUnitCharge        // aka actions storage
	PricingMeterDailyUnitCharge          // aka high watermark
)

var DeprecatedLicensedSKUs = map[string]struct{}{
	"ghec_seats": {},
	"ghas_seats": {},
}

func ToPricingType(t proto.PricingMeterType) PricingMeterType {
	return PricingMeterType(t)
}

func (b PricingMeterType) ToProto() proto.PricingMeterType {
	return proto.PricingMeterType(b)
}

func (b PricingMeterType) String() string {
	switch b {
	case PricingMeterDefault:
		return "default"
	case PricingMeterPerHourUnitCharge:
		return "per-hour-unit-charge"
	case PricingMeterDailyUnitCharge:
		return "daily-unit-charge"
	default:
		return fmt.Sprintf("%d", int(b))
	}
}

type Priced interface {
	GetProduct() string
}

type OldPrice struct {
	Price              float64
	Sku                string
	FriendlyName       string
	Product            string
	AzureMeterId       string
	MeterType          PricingMeterType
	FreeForPublicRepos bool
	EffectiveAt        int64
	UnitType           UnitType
}

func (price *OldPrice) IsEnabled(at time.Time) bool {
	return price.EffectiveAt <= at.Unix()
}

type HistoricalPrice struct {
	StartDate int64
	EndDate   int64
	Price     int64
}

func (h *HistoricalPrice) ToProto() *proto.HistoricalPrice {
	return &proto.HistoricalPrice{
		StartDate: h.StartDate,
		EndDate:   h.EndDate,
		Price:     ToDecimalAmount(h.Price),
	}
}

// **Pricing**
// pricing is a struct that represents the pricing of a product
type Pricing struct {
	*Key
	Price               int64 // we're storing all prices as 10000th of a dollar as our smallest unit is 0.008 dollars
	Product             string
	Sku                 string
	MeterType           PricingMeterType
	FriendlyName        string
	AzureMeterId        string
	EffectiveDatePrices []HistoricalPrice
	FreeForPublicRepos  bool
	EffectiveAt         int64
	UnitType            UnitType
}

type PricingSelectionData struct {
	TargetTime int64
	ProductSku string
	AccountId  int64
}

/*

use this to find max avaliable amount
for i := int64(92233720366); i < math.MaxInt64; i++ {
	x := float64(i)
	converted := ToWholeAmount[int64](x)
	back := ToDecimalAmount(converted)
	if back != x {
		t.Errorf("got to %d", i)
		t.Fail()
	}
	i++
}
*/

const (
	// A variable of type int64 can store integers ranging from -9223372036854775808 til **9223372036854775807.
	// With this converstion factor that leaves us with 92 trillion dollars as our max unit
	// we have real world storage data at 0.000000067 units so making 9 our max precision
	// with 9 digits of precision largest number: 9,223,372,036
	// this means
	// 		the largest quantity for a price of 1 is 9223372036
	//		the largest price for a quantity of 1 is 9223372036
	//		the largest billingAmount for a given price*sku is 9223372036
	ToNanoCents                         float64 = 1000000000
	unit                                float64 = 0.0000000005
	PricingMinimumSupportedDecimalPrice float64 = 0.000000001 // a nano cent
	PricingMaximumSupportedDecimalPrice float64 = 9223372036
	PricingMaxValueAsNano               int64   = 9223372036000000000
)

const (
	NanoZeroTenThousands int64 = int64(0.0001 * ToNanoCents)
	NanoZeroThousandths  int64 = int64(0.001 * ToNanoCents)
	NanoZeroHundreds     int64 = int64(0.01 * ToNanoCents)
	NanoZeroTenths       int64 = int64(0.1 * ToNanoCents)
	NanoOne              int64 = 1 * int64(ToNanoCents)
	NanoTen              int64 = 10 * int64(ToNanoCents)
	NanoHundred          int64 = 100 * int64(ToNanoCents)
	NanoThousand         int64 = 1000 * int64(ToNanoCents)
	NanoMillion          int64 = 1000000 * int64(ToNanoCents)
	NanoBillion          int64 = 1000000000 * int64(ToNanoCents)
)

func ToWholeAmount[T int64 | uint64](price float64) T {
	// round it to the nearest whole number for precision greater than 10
	// this handles 4.1 == 4.0999999999999996447286321199499070644378662109375 rounding the float
	priceByUnit := price / unit        // 4.1 * 0.000005 = 819999.9999999999
	rounded := math.Round(priceByUnit) // 819999.9999999999 -> 820000
	backToFloat := rounded * unit      // 4.1000000000000005
	// this convertes to the whole number
	x := backToFloat * ToNanoCents // 410000.00000000006
	ret := T(x)                    // 410000

	// 99.999999, which is 1 digit past our max precision rounds up to 100 which is wrong
	// but its an edge case that we can live with. the string implemention works but is much slower
	// I don't know if it matters if its slower but accurate
	if ToDecimalAmount(ret) != price {
		return ToWholeAmountString[T](price)
	}
	return ret
}

func ToWholeAmountString[T int64 | uint64](price float64) T {
	c := price * ToNanoCents
	s := fmt.Sprintf("%.05f", c)
	f, _ := strconv.ParseFloat(s, 64)
	i := T(f)
	return i
}

func ToDecimalAmount[T int64 | uint64](price T) float64 {
	return float64(price) / ToNanoCents
}

func NewHistoricalPricesAsWholeAmountFromProto(prices []*proto.HistoricalPrice) []HistoricalPrice {
	historicalPrices := make([]HistoricalPrice, len(prices))
	for i, e := range prices {
		historicalPrices[i] = HistoricalPrice{
			StartDate: e.GetStartDate(),
			EndDate:   e.GetEndDate(),
			Price:     ToWholeAmount[int64](e.GetPrice()),
		}
	}
	return historicalPrices
}

func NewPricingFromProto(pricing *proto.Pricing) (*Pricing, error) {
	effectiveDatePrices := NewHistoricalPricesAsWholeAmountFromProto(pricing.GetEffectiveDatePrices())

	return NewPricingAsWholeAmountWithMeterType(pricing.GetSku(),
		pricing.GetProduct(),
		pricing.GetPrice(),
		PricingMeterType(pricing.GetMeterType()),
		pricing.GetFriendlyName(),
		pricing.GetAzureMeterId(),
		effectiveDatePrices,
		pricing.GetFreeForPublicRepos(),
		pricing.GetEffectiveAt(),
		UnitType(pricing.GetUnitType()),
	)
}

// Only for unit tests
func NewPricingAsWholeAmount(sku string, product string, price float64) (*Pricing, error) {
	return NewPricingAsWholeAmountWithMeterType(sku, product, price, PricingMeterDefault, "", "", []HistoricalPrice{}, false, time.Now().UTC().Unix(), UnitTypeUnknown)
}

func NewPricingAsWholeAmountWithMeterType(
	sku string,
	product string,
	price float64,
	meterType PricingMeterType,
	friendlyName string,
	azureMeterId string,
	effectiveDatePrices []HistoricalPrice,
	freeForPublicRepos bool,
	effectiveAt int64,
	unitType UnitType,
) (*Pricing, error) {

	if price != 0 && (price < PricingMinimumSupportedDecimalPrice || price > PricingMaximumSupportedDecimalPrice) {
		return nil, fmt.Errorf("price must be between %f and %f, %s, %s, %f, %s, %s", PricingMinimumSupportedDecimalPrice, PricingMaximumSupportedDecimalPrice, sku, product, price, meterType, friendlyName)
	}

	convertedPrice := ToWholeAmount[int64](price)
	if convertedPrice < 0 {
		return nil, fmt.Errorf("price must be 0 or greater than minsupported price of %f", PricingMinimumSupportedDecimalPrice)
	}
	return &Pricing{
		Key:                 NewPricingKey(sku),
		Sku:                 sku,
		Product:             product,
		Price:               convertedPrice,
		MeterType:           meterType,
		FriendlyName:        friendlyName,
		AzureMeterId:        azureMeterId,
		EffectiveDatePrices: effectiveDatePrices,
		FreeForPublicRepos:  freeForPublicRepos,
		EffectiveAt:         effectiveAt,
		UnitType:            unitType,
	}, nil

}

func (pricing *Pricing) ToProto() *proto.Pricing {
	effectiveDatePrices := make([]*proto.HistoricalPrice, len(pricing.EffectiveDatePrices))
	for i, e := range pricing.EffectiveDatePrices {
		effectiveDatePrices[i] = e.ToProto()
	}

	return &proto.Pricing{
		Sku:                 pricing.GetSku(),
		Price:               ToDecimalAmount(pricing.GetPrice()),
		Product:             pricing.GetProduct(),
		MeterType:           pricing.MeterType.ToProto(),
		FriendlyName:        pricing.GetFriendlyName(),
		AzureMeterId:        pricing.AzureMeterId,
		EffectiveDatePrices: effectiveDatePrices,
		FreeForPublicRepos:  pricing.GetFreeForPublicRepos(),
		EffectiveAt:         pricing.EffectiveAt,
		UnitType:            pricing.UnitType.ToProto(),
	}
}

func NewPricingKey(sku string) *Key {
	return &Key{
		Id:           sku,
		PartitionKey: "pricing",
	}
}

func (billingItem *Item) ApplyPricing(pricing *Pricing) {
	currentPricing := pricing.Price

	nanoPricing := nano.NewFromInt(currentPricing)
	nanoQuantity := nano.NewFromInt(billingItem.Quantity)

	result := nanoPricing.Mul(nanoQuantity)

	billingItem.BilledAmount = result.Int64()
	billingItem.AppliedCostPerQuantity = currentPricing

	billingItem.Pricing = pricing
}

// CalculateQuantity This is the opposite of ApplyPricing
// Given a billed amount, calculate the quantity based on the price
// essentially (billedAmount/pricing)
func (pricing Pricing) CalculateQuantity(billedAmount int64) int64 {
	nanoPricing := nano.NewFromInt(pricing.Price)
	nanoBilledAmount := nano.NewFromInt(billedAmount)

	result := nanoBilledAmount.Div(nanoPricing)

	return result.Int64()
}

func (pricing *Pricing) GetProduct() string {
	if pricing != nil {
		return pricing.Product
	}
	return ""
}

func (pricing *Pricing) GetSku() string {
	if pricing != nil {
		return pricing.Sku
	}
	return ""
}

func (pricing *Pricing) GetPrice() int64 {
	if pricing != nil {
		return pricing.Price
	}
	return 0
}

func (pricing *Pricing) GetFreeForPublicRepos() bool {
	if pricing != nil {
		return pricing.FreeForPublicRepos
	}
	return false
}

func (pricing *Pricing) GetFriendlyName() string {
	if pricing != nil {
		return pricing.FriendlyName
	}
	return ""
}

func (pricing *Pricing) IsEnabled(at time.Time) bool {
	return pricing.EffectiveAt <= at.Unix()
}

func (pricing *Pricing) isDeprecatedLicensedSku() bool {
	_, deprecated := DeprecatedLicensedSKUs[pricing.Sku]
	return deprecated
}

func (pricing *Pricing) IsLicensedSkuWithDailyEmission() bool {
	unitTypeIsUserMonths := pricing.UnitType == UnitTypeUserMonths
	return unitTypeIsUserMonths && !pricing.isDeprecatedLicensedSku()
}
