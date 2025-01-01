package models

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/pkg/errors"
)

type InvoicePeriod string

const (
	InvoiceMonthly InvoicePeriod = "monthly"
	InvoiceDaily   InvoicePeriod = "daily"
)

type InvoiceState string

const (
	Active    InvoiceState = "active"
	Submitted InvoiceState = "submitted"
	Confirmed InvoiceState = "confirmed"
	Rejected  InvoiceState = "rejected"
)

type ProductTotal struct {
	Product    string
	UsageTotal *UsageTotal
	SkuTotals  map[string]*SkuTotal
}

type ProductTotalNano struct {
	Product    string
	UsageTotal *UsageTotalNano
	SkuTotals  map[string]*SkuTotalNano
}

func (p *ProductTotal) ToProto() *proto.ProductTotal {
	SkuTotals := make(map[string]*proto.SkuTotal)
	for sku, skuTotal := range p.SkuTotals {
		SkuTotals[sku] = skuTotal.ToProto()
	}
	return &proto.ProductTotal{Product: p.Product,
		UsageTotal: p.UsageTotal.ToProto(),
		SkuTotals:  SkuTotals}
}

type SkuTotal struct {
	Sku          string
	UsageTotal   *UsageTotal
	BillingItems []*Item
}

type SkuTotalNano struct {
	Sku          string
	UsageTotal   *UsageTotalNano
	BillingItems []*Item
}

func (s *SkuTotal) ToProto() *proto.SkuTotal {
	var BillingItems []*proto.BillingItem
	for _, item := range s.BillingItems {
		BillingItems = append(BillingItems, item.ToProto())
	}
	return &proto.SkuTotal{
		Sku:          s.Sku,
		UsageTotal:   s.UsageTotal.ToProto(),
		BillingItems: BillingItems}

}

type GenericUsageTotal[T any] struct {
	Gross    T
	Discount T
	Net      T
	Quantity T
}

type UsageTotal GenericUsageTotal[float64]
type UsageTotalNano GenericUsageTotal[int64]

func (u *UsageTotal) ToProto() *proto.UsageTotal {
	return &proto.UsageTotal{Gross: u.Gross,
		Discount: u.Discount,
		Net:      u.Net,
		Quantity: u.Quantity}
}

type InvoicePartitionDetail struct {
	CustomerId string
	Period     InvoicePeriod
	Year       int64
	Month      int64
	Day        int64 `json:",omitempty"`
}

func (ipd *InvoicePartitionDetail) IsValid() bool {
	// Both a year and month must be provided
	return ipd.Year != 0 && ipd.Month != 0 && (ipd.Period != InvoiceDaily || ipd.Day != 0)
}

type Invoice struct {
	*Key
	Uuid          string // do we need this?
	CustomerId    string
	Period        InvoicePeriod
	Year          int64
	Month         int64
	Day           int64 `json:",omitempty"`
	UsageTotal    *UsageTotal
	ProductTotals map[string]*ProductTotal
	State         InvoiceState
}

type Totals struct {
	UsageTotal    *UsageTotalNano
	ProductTotals map[string]*ProductTotalNano
}

type ActiveInvoicesItem struct {
	*Key
	// When the item is processed by the generation dispatcher
	ProcessedAt *time.Time
}

type SubmittedInvoicesItem struct {
	*Key
	// When the item is submitted/emitted
	SubmittedAt *time.Time
}

type ConfirmedInvoicesItem struct {
	*Key
	// When the item is confirmed (Zuora only)
	ConfirmedAt *time.Time
}

type RejectedInvoicesItem struct {
	*Key
	ErrorCode    string
	ErrorMessage string
	RejectedAt   *time.Time
}

func NewInvoiceKey(ipd *InvoicePartitionDetail) *Key {
	partitionKey := CustomerIdToInvoicePartitionKey(ipd.CustomerId)
	id := fmt.Sprintf("%s:%d:%d", partitionKey, ipd.Year, ipd.Month)

	if ipd.Period != InvoiceMonthly && ipd.Day != 0 {
		id = fmt.Sprintf("%s:%d", id, ipd.Day)
	}

	return &Key{
		PartitionKey: partitionKey,
		Id:           id,
	}
}

func NewInvoice(ipd *InvoicePartitionDetail, items []*Item, discountItems []*DiscountItem) *Invoice {
	invoice := &Invoice{
		Key:           NewInvoiceKey(ipd),
		CustomerId:    ipd.CustomerId,
		Period:        ipd.Period,
		Year:          ipd.Year,
		Month:         ipd.Month,
		UsageTotal:    &UsageTotal{},
		ProductTotals: map[string]*ProductTotal{},
		State:         Active,
	}
	totals := &Totals{
		UsageTotal:    &UsageTotalNano{},
		ProductTotals: map[string]*ProductTotalNano{},
	}

	for _, item := range items {
		product := item.GetProduct()
		sku := item.GetSku()
		productTotal, ok := totals.ProductTotals[product]
		if !ok {
			productTotal = &ProductTotalNano{
				Product:    product,
				UsageTotal: &UsageTotalNano{},
				SkuTotals:  map[string]*SkuTotalNano{},
			}
			totals.ProductTotals[product] = productTotal
		}

		skuTotal, ok := productTotal.SkuTotals[sku]
		if !ok {
			skuTotal = &SkuTotalNano{
				Sku:        sku,
				UsageTotal: &UsageTotalNano{},
			}
			productTotal.SkuTotals[sku] = skuTotal
		}
		if item.Amounts != nil {
			SaveBillingAmounts(skuTotal.UsageTotal, item)
			SaveBillingAmounts(productTotal.UsageTotal, item)
			SaveBillingAmounts(totals.UsageTotal, item)
		}
		skuTotal.BillingItems = append(skuTotal.BillingItems, item)
	}

	for _, item := range discountItems {
		ApplyDiscount(totals.UsageTotal, item)
		productTotal := totals.ProductTotals[item.asBillingItem().GetProduct()]
		ApplyDiscount(productTotal.UsageTotal, item)
		ApplyDiscount(productTotal.SkuTotals[item.asBillingItem().GetSku()].UsageTotal, item)
	}

	return AddTotalsToInvoice(invoice, totals)
}

func AddTotalsToInvoice(invoice *Invoice, totals *Totals) *Invoice {
	invoice.UsageTotal = ConvertTotalsToFloats(invoice.UsageTotal, totals.UsageTotal)
	for product, productTotals := range totals.ProductTotals {
		skuTotalsNano := map[string]*SkuTotal{}
		for sku, skuTotals := range productTotals.SkuTotals {
			skuTotalsNano[sku] = &SkuTotal{
				Sku:          sku,
				UsageTotal:   ConvertTotalsToFloats(&UsageTotal{}, skuTotals.UsageTotal),
				BillingItems: skuTotals.BillingItems,
			}
		}

		invoice.ProductTotals[product] = &ProductTotal{
			Product:    product,
			UsageTotal: ConvertTotalsToFloats(&UsageTotal{}, productTotals.UsageTotal),
			SkuTotals:  skuTotalsNano,
		}

	}

	return invoice
}

func ConvertTotalsToFloats(floatTotals *UsageTotal, nanoTotals *UsageTotalNano) *UsageTotal {
	floatTotals.Gross = ToDecimalAmount(nanoTotals.Gross)
	floatTotals.Discount = ToDecimalAmount(nanoTotals.Discount)
	floatTotals.Net = ToDecimalAmount(nanoTotals.Net)
	floatTotals.Quantity = ToDecimalAmount(nanoTotals.Quantity)

	return floatTotals
}

func NewActiveInvoiceItem(ipd *InvoicePartitionDetail, processedAt *time.Time) *ActiveInvoicesItem {
	return &ActiveInvoicesItem{
		Key:         GetInvoiceItemKey(ipd, Active),
		ProcessedAt: processedAt,
	}
}

func NewSubmittedInvoiceItem(ipd *InvoicePartitionDetail, submittedAt *time.Time) *SubmittedInvoicesItem {
	return &SubmittedInvoicesItem{
		Key:         GetInvoiceItemKey(ipd, Submitted),
		SubmittedAt: submittedAt,
	}
}

func NewConfirmedInvoiceItem(ipd *InvoicePartitionDetail, confirmedAt *time.Time) *ConfirmedInvoicesItem {
	return &ConfirmedInvoicesItem{
		Key:         GetInvoiceItemKey(ipd, Confirmed),
		ConfirmedAt: confirmedAt,
	}
}

func NewRejectedInvoiceItem(ipd *InvoicePartitionDetail, errorCode string, errorMessage string, rejectedAt *time.Time) *RejectedInvoicesItem {
	return &RejectedInvoicesItem{
		Key:          GetInvoiceItemKey(ipd, Rejected),
		ErrorCode:    errorCode,
		ErrorMessage: errorMessage,
		RejectedAt:   rejectedAt,
	}
}

func GetInvoiceItemKey(ipd *InvoicePartitionDetail, state InvoiceState) *Key {
	return &Key{
		PartitionKey: InvoiceItemPartitionKey(ipd, state),
		Id:           NewInvoiceKey(ipd).Id,
	}
}

func InvoiceItemPartitionKey(ipd *InvoicePartitionDetail, state InvoiceState) string {
	key := fmt.Sprintf("invoices:%s:%d:%d", state, ipd.Year, ipd.Month)

	if ipd.Period != InvoiceMonthly && ipd.Day != 0 {
		key = fmt.Sprintf("%s:%d", key, ipd.Day)
	}

	return key
}

func InvoicePartitionDetailFromInvoiceKey(invoiceKey *Key) (*InvoicePartitionDetail, error) {
	// customer:id:invoices:year:month?:day
	id := invoiceKey.Id
	parts := strings.Split(id, ":")
	customerId := parts[1]
	period := InvoiceMonthly
	year, err := strconv.Atoi(parts[3])
	if err != nil {
		return nil, errors.Wrap(err, "failed to parse year")
	}
	month, err := strconv.Atoi(parts[4])
	if err != nil {
		return nil, errors.Wrap(err, "failed to parse month")
	}

	day := 0
	if len(parts) > 5 {
		period = InvoiceDaily
		dayInt, err := strconv.Atoi(parts[5])
		if err != nil {
			return nil, errors.Wrap(err, "failed to parse day")
		}

		day = dayInt
	}

	return &InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     period,
		Year:       int64(year),
		Month:      int64(month),
		Day:        int64(day),
	}, nil
}

func InvoiceKeyFromActiveInvoiceKey(activeInvoiceKey *Key) *Key {
	id := activeInvoiceKey.Id
	// convert customer:id:invoices:year:month to customer:id:invoices
	parts := strings.Split(id, ":")
	partitionKey := strings.Join(parts[:3], ":")

	return &Key{
		PartitionKey: partitionKey,
		Id:           id,
	}
}

func (invoice *Invoice) ToProto() *proto.Invoice {
	ProductTotals := make(map[string]*proto.ProductTotal)
	for product, productTotals := range invoice.ProductTotals {
		ProductTotals[product] = productTotals.ToProto()
	}

	return &proto.Invoice{
		CustomerId:    invoice.CustomerId,
		Year:          invoice.Year,
		Month:         invoice.Month,
		UsageTotal:    invoice.UsageTotal.ToProto(),
		ProductTotals: ProductTotals,
	}
}

func ApplyDiscount(usageTotal *UsageTotalNano, item *DiscountItem) {
	usageTotal.Discount += item.DiscountAmount
	usageTotal.Net -= item.DiscountAmount
}

func SaveBillingAmounts(usageTotal *UsageTotalNano, item *Item) {
	usageTotal.Gross += item.BilledAmount
	usageTotal.Net += item.BilledAmount
	usageTotal.Quantity += item.Quantity
}
