//go:build integration
// +build integration

package integrationtests_test

import (
	"context"
	"fmt"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	a "github.com/github/billing-platform/testing/assertions"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_Discount_When_ADollar_Discount_Created(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()
	pricing := client.EnsureSpecificPricingExists(20.0, "actions_linux", "actions", "")

	yesterday := time.Now().AddDate(0, 0, -1)
	nextYear := time.Now().AddDate(1, 0, 0)
	discount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing.Sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
			{
				Id:   "actions",
				Type: proto.DiscountTargetType_ProductDiscount,
			},
		},
		10.0,
		yesterday.Unix(),
		nextYear.Unix(),
	)
	createDiscountResponse, err := client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount")
	g.Expect(createDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	discountResponse, err := client.GetDiscount(customerId, createDiscountResponse.Uuid)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "get discount")
	g.Expect(discountResponse.Discount.Uuid).Should(gomega.Equal(createDiscountResponse.Uuid))
	g.Expect(discountResponse.Discount.CustomerId).Should(gomega.Equal(customerId))
	g.Expect(discountResponse.Discount.Percentage).Should(gomega.Equal(0.0))
	g.Expect(discountResponse.Discount.TargetAmount).Should(gomega.Equal(10.0))
	g.Expect(discountResponse.Discount.StartDate).Should(gomega.Equal(yesterday.Truncate(time.Hour * 24).Unix()))
	g.Expect(discountResponse.Discount.EndDate).Should(gomega.Equal(nextYear.Truncate(time.Hour * 24).Unix()))
	g.Expect(len(discountResponse.Discount.Targets)).Should(gomega.Equal(2))
	g.Expect(discountResponse.Discount.Targets[0].Id).Should(gomega.Equal(pricing.Sku))
	g.Expect(discountResponse.Discount.Targets[0].Type).Should(gomega.Equal(proto.DiscountTargetType_SkuDiscount))
	g.Expect(discountResponse.Discount.Targets[1].Id).Should(gomega.Equal("actions"))
	g.Expect(discountResponse.Discount.Targets[1].Type).Should(gomega.Equal(proto.DiscountTargetType_ProductDiscount))
}

func Test_Discount_CreatePercentageDiscount_DeniesDiscountOfMoreThan100(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()
	sku := "test sku 2"
	percentageDiscount := 100.0001

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()
	discount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		percentageDiscount,
		yesterday,
		nextYear,
	)

	_, err := client.CreateDiscount(discount)
	g.Expect(err).To(gomega.HaveOccurred())
}

func Test_Discount_When_APercentageDiscount_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	price := 20.0
	pricing := client.EnsureSpecificPricingExists(price, "actions_linux_64_core", "actions", "Actions")

	quantity := 1.0

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()
	discount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing.Sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		10.0,
		yesterday,
		nextYear,
	)

	discountResponse, err := client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount")
	g.Expect(discountResponse.Uuid).ShouldNot(gomega.BeNil())

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerId, usageDate)
	usage1.Entity.OrganizationId = 0 // to additionally test for usage without org id (e.g. usage from individuals)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	// after the daily job, get usage from daily bucket from final total
	u := client.GetUsageTotal("", pricing.Sku, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*2), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(40.0), "usage Amount")

	uDiscount := client.GetDiscountTotal(pricing.Sku, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(0.2), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(4.0), "discount Amount")

	client.RunMonthlyJob(len(usages))

	// after the monthly job, get usage from monthly bucket from final total
	u = client.GetUsageTotal("", pricing.Sku, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*2), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(40.0), "usage Amount")

	uDiscount = client.GetDiscountTotal(pricing.Sku, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(0.2), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(4.0), "discount Amount")

	client.RunYearlyJob(len(usages))

	// after the monthly job, get usage from monthly bucket from final total
	u = client.GetUsageTotal("", pricing.Sku, customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*2), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(40.0), "usage Amount")

	uDiscount = client.GetDiscountTotal(pricing.Sku, customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(0.2), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(4.0), "discount Amount")
}

func Test_Discount_When_TwoPercentageDiscounts_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	price := 20.0
	pricing := client.EnsureSpecificPricingExists(price, "actions_linux_64_core", "actions", "Actions")

	quantity := 1.0

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()
	discount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing.Sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		10.0,
		yesterday,
		nextYear,
	)

	discountResponse, err := client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount")
	g.Expect(discountResponse.Uuid).ShouldNot(gomega.BeNil())

	enterpriseDiscount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   customerId,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		100.0,
		yesterday,
		nextYear,
	)

	enterpriseDiscountResponse, err := client.CreateDiscount(enterpriseDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount")
	g.Expect(enterpriseDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetUsageTotal("", pricing.Sku, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*2), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(40.0), "usage Amount")

	uDiscount := client.GetDiscountTotal(pricing.Sku, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(quantity*2), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(40.0), "discount Amount")
}

func Test_Discount_When_ADollarDiscount_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	price := 20.0
	pricing := client.EnsureSpecificPricingExists(price, "actions_linux_4_core", "actions", "")

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()
	skuDiscount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing.Sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		20.0,
		yesterday,
		nextYear,
	)
	skuDiscountResponse, err := client.CreateDiscount(skuDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create SKU discount")
	g.Expect(skuDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	productDiscount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   "actions",
				Type: proto.DiscountTargetType_ProductDiscount,
			},
		},
		45.0,
		yesterday,
		nextYear,
	)
	productDiscountResponse, err := client.CreateDiscount(productDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create product discount")
	g.Expect(productDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	repoId := stubs.GetRandomId64()
	repoDiscount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   fmt.Sprintf("%d", repoId),
				Type: proto.DiscountTargetType_RepoDiscount,
			},
		},
		5.0,
		yesterday,
		nextYear,
	)
	repoDiscountResponse, err := client.CreateDiscount(repoDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create repo discount")
	g.Expect(repoDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	orgId := stubs.GetRandomId64()
	orgDiscount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   fmt.Sprintf("%d", orgId),
				Type: proto.DiscountTargetType_OrgDiscount,
			},
		},
		5.0,
		yesterday,
		nextYear,
	)
	orgDiscountResponse, err := client.CreateDiscount(orgDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create org discount")
	g.Expect(orgDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	enterpriseDiscount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   customerId,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		10.0,
		yesterday,
		nextYear,
	)
	enterpriseDiscountResponse, err := client.CreateDiscount(enterpriseDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create enterprise discount")
	g.Expect(enterpriseDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	quantity := 1.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)

	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}

	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity) // 20 goes to Product discount 20/45
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity) // 20 goes to Product discount 40/45, no longer the largest dollar discount
	usage3 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity) // 20 goes to SKU discount 20/20
	usage4 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity) // 10 goes to Enterprise discount 10/10, 10 leftover
	usage5 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity) // 5 goes to Product discount 45/45, 15 leftover

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5})
	client.RunUsageIngestion(5)

	cs := client.GetDiscountState(customerId, productDiscountResponse.Uuid, time.Now().UTC())
	g.Expect(cs.DiscountState.IsFullyApplied).Should(gomega.Equal(true), "product discount IsFullyApplied")
	g.Expect(cs.DiscountState.CurrentAmount).Should(gomega.Equal(45.0), "product discount CurrentAmount")

	cs = client.GetDiscountState(customerId, skuDiscountResponse.Uuid, time.Now().UTC())
	g.Expect(cs.DiscountState.IsFullyApplied).Should(gomega.Equal(true), "sku discount IsFullyApplied")
	g.Expect(cs.DiscountState.CurrentAmount).Should(gomega.Equal(20.0), "sku discount CurrentAmount")

	cs = client.GetDiscountState(customerId, enterpriseDiscountResponse.Uuid, time.Now().UTC())
	g.Expect(cs.DiscountState.IsFullyApplied).Should(gomega.Equal(true), "enterprise discount IsFullyApplied")
	g.Expect(cs.DiscountState.CurrentAmount).Should(gomega.Equal(10.0), "enterprise discount CurrentAmount")

	cs = client.GetDiscountState(customerId, repoDiscountResponse.Uuid, time.Now().UTC())
	g.Expect(cs.DiscountState).Should(gomega.BeNil(), "repo discount state should not be created (aka never applied)")

	cs = client.GetDiscountState(customerId, orgDiscountResponse.Uuid, time.Now().UTC())
	g.Expect(cs.DiscountState).Should(gomega.BeNil(), "org discount state should not be created (aka never applied)")

	client.RunMonthlyJob(5)

	uDiscount := client.GetDiscountTotal(pricing.Sku, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(3.75), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(75.0), "discount Amount")
}

func Test_Discount_Largest_Applicable_Discount_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	yesterday := time.Now().UTC().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().UTC().AddDate(1, 0, 0).Unix()
	inTwoYears := time.Now().UTC().AddDate(2, 0, 0).Unix()

	expiredDiscount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   customerId,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		10.0,
		nextYear,
		inTwoYears,
	)
	_, _ = client.CreateDiscount(expiredDiscount)

	discount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   customerId,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		10.0,
		yesterday,
		nextYear,
	)
	_, _ = client.CreateDiscount(discount)

	skuDiscount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   "actions_linux",
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		10.05,
		yesterday,
		nextYear,
	)
	_, _ = client.CreateDiscount(skuDiscount)

	discountQuantity := 50_000.0
	quantity := 10_000.0
	usageDate := time.Date(2023, 7, 15, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), "actions_linux", discountQuantity, customerId, usageDate) // Plan discount applied first 400/400 = 0
	usage2 := stubs.CreateUsage(uuid.NewString(), "actions_linux", quantity, customerId, usageDate)         // 80 - 10.05 from SKU plan discount becomes 69.95
	usage3 := stubs.CreateUsage(uuid.NewString(), "actions_linux", quantity, customerId, usageDate)         // 80 becomes 72 after 10% resulting in 72 + 69.955 = 141.955 of total after applying discounts

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage1})

	client.RunUsageIngestion(1)
	client.RunDailyJob(1)
	client.RunMonthlyJob(1)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage2})

	client.RunUsageIngestion(1)
	client.RunDailyJob(1)
	client.RunMonthlyJob(1)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage3})

	client.RunUsageIngestion(1)
	client.RunDailyJob(1)
	client.RunMonthlyJob(1)

	u := client.GetUsageTotal("", "actions_linux", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(discountQuantity+(quantity*2)), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(560.0), "usage Amount")

	uDiscount := client.GetDiscountTotal("actions_linux", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(418.05), "discount Amount") // 400 from plan + 10.05 from dollar + 8.00 from percentage
	// plan discount: amount of 400 / 0.008 price = 50_000 quantity (mins)
	// dollar discount: 10.05 / 0.008 price = 1_256.25 quantity (mins)
	// dollar discount: (10_000 * 0.008 price * 10% discount) / 0.008 price = 1_000.00 quantity (mins)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(52_256.25), "discount quantity")

	u = client.GetUsageTotal("", "actions_linux", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(discountQuantity+(quantity*2)), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(560.0), "usage Amount")

	uDiscount = client.GetDiscountTotal("actions_linux", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(52_256.25), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(418.05), "discount Amount")
}

func Test_Discount_Get_All_Discounts(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()
	enterpriseDiscount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   customerId,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		10.0,
		yesterday,
		nextYear,
	)

	enterpriseDiscountResponse, err := client.CreateDiscount(enterpriseDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create enterprise discount")
	g.Expect(enterpriseDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	skuDiscount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   "actions_linux",
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		10.05,
		yesterday,
		nextYear,
	)

	skuDiscountResponse, err := client.CreateDiscount(skuDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create SKU discount")
	g.Expect(skuDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	allDiscountsResponse, err := client.GetAllDiscounts(customerId)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "get all discounts")
	g.Expect(len(allDiscountsResponse.Discounts)).Should(gomega.Equal(2))

	g.Expect(allDiscountsResponse.Discounts[0].Uuid).Should(gomega.Equal(enterpriseDiscountResponse.Uuid))
	g.Expect(allDiscountsResponse.Discounts[0].CustomerId).Should(gomega.Equal(customerId))
	g.Expect(allDiscountsResponse.Discounts[0].Percentage).Should(gomega.Equal(10.0))
	g.Expect(allDiscountsResponse.Discounts[0].TargetAmount).Should(gomega.Equal(0.0))
	g.Expect(len(allDiscountsResponse.Discounts[0].Targets)).Should(gomega.Equal(1))
	g.Expect(allDiscountsResponse.Discounts[0].Targets[0].Id).Should(gomega.Equal(customerId))
	g.Expect(allDiscountsResponse.Discounts[0].Targets[0].Type).Should(gomega.Equal(proto.DiscountTargetType_EnterpriseDiscount))

	g.Expect(allDiscountsResponse.Discounts[1].Uuid).Should(gomega.Equal(skuDiscountResponse.Uuid))
	g.Expect(allDiscountsResponse.Discounts[1].CustomerId).Should(gomega.Equal(customerId))
	g.Expect(allDiscountsResponse.Discounts[1].Percentage).Should(gomega.Equal(0.0))
	g.Expect(allDiscountsResponse.Discounts[1].TargetAmount).Should(gomega.Equal(10.05))
	g.Expect(len(allDiscountsResponse.Discounts[1].Targets)).Should(gomega.Equal(1))
	g.Expect(allDiscountsResponse.Discounts[1].Targets[0].Id).Should(gomega.Equal("actions_linux"))
	g.Expect(allDiscountsResponse.Discounts[1].Targets[0].Type).Should(gomega.Equal(proto.DiscountTargetType_SkuDiscount))
}

func Test_Discount_Get_All_Discount_States_When_Customer_No_Exist(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	allDiscountStates := client.GetAllDiscountStates("non-existing-customer", time.Now().UTC()).Discounts
	g.Expect(len(allDiscountStates)).Should(gomega.Equal(0), "no discount states for customer that doesn't exist")
}

func Test_Discount_Get_All_Discount_States(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	price := 20.0
	pricing := client.EnsureSpecificPricingExists(price, "actions_linux_4_core", "actions", "")

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()

	orgId := stubs.GetRandomId64()

	enterpriseDiscount := stubs.CreateDollarDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   customerId,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		10.0,
		yesterday,
		nextYear,
	)
	enterpriseDiscountResponse, err := client.CreateDiscount(enterpriseDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create enterprise discount")
	g.Expect(enterpriseDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	percentageDiscount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   customerId,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		10.0,
		yesterday,
		nextYear,
	)

	percentageDiscountResponse, err := client.CreateDiscount(percentageDiscount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create percentage discount")
	g.Expect(percentageDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	quantity := 1.0
	usageDate := time.Now().UTC()

	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	privateRepoId := stubs.GetRandomId64()
	_ = client.CreateRepo(privateRepoId, false)
	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         privateRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity)
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity)
	usage3 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity)
	usage4 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity)
	usage5 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity)
	usage6 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", 10000.0, usageDate, entity)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	ds1 := client.GetDiscountState(customerId, enterpriseDiscountResponse.Uuid, time.Now().UTC())
	g.Expect(ds1.DiscountState.IsFullyApplied).Should(gomega.Equal(true), "enterprise discount IsFullyApplied")
	// 5 quantity * $20/unit = $100 of usage, with $10 off, the current amount is 10$
	g.Expect(ds1.DiscountState.CurrentAmount).Should(gomega.Equal(10.0), "enterprise discount CurrentAmount")

	ds2 := client.GetDiscountState(customerId, percentageDiscountResponse.Uuid, time.Now().UTC())
	// percentage discounts are never considered as fully applied
	g.Expect(ds2.DiscountState.IsFullyApplied).Should(gomega.Equal(false), "percentage discount IsFullyApplied")
	// 4 quantity * $20/unit = $80 of usage; 10 * 10% = $8, the CurrentAmount
	g.Expect(ds2.DiscountState.CurrentAmount).Should(gomega.Equal(8.0), "percentage discount CurrentAmount")

	allDiscountStates := client.GetAllDiscountStates(customerId, time.Now().UTC()).Discounts
	// Although we have 2 discounts created in the test, there are 4 hardcoded plan discounts as well
	g.Expect(len(allDiscountStates)).Should(gomega.Equal(8), "all discount states found")
	g.Expect(allDiscountStates[0].IsFullyApplied).Should(gomega.Equal(ds1.DiscountState.IsFullyApplied))
	g.Expect(allDiscountStates[1].IsFullyApplied).Should(gomega.Equal(ds2.DiscountState.IsFullyApplied))

	g.Expect(allDiscountStates[0].Uuid).Should(gomega.Equal(enterpriseDiscountResponse.Uuid))
	g.Expect(allDiscountStates[1].Uuid).Should(gomega.Equal(percentageDiscountResponse.Uuid))

	g.Expect(allDiscountStates[0].CurrentAmount).Should(gomega.Equal(ds1.DiscountState.CurrentAmount))
	g.Expect(allDiscountStates[1].CurrentAmount).Should(gomega.Equal(ds2.DiscountState.CurrentAmount))
	g.Expect(allDiscountStates[1].Percentage).Should(gomega.Equal(10.0))

	// This verifies that the plan discount current amount was updated properly
	// 10_000 quantity * $0.008 = $80.0
	g.Expect(allDiscountStates[2].CurrentAmount).Should(gomega.Equal(80.0))
	g.Expect(allDiscountStates[2].IsFullyApplied).Should(gomega.Equal(false))
}

func Test_Discount_Get_All_Discount_States_Returns_Public_Repo_Discount_State(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customer.CustomerId
	_ = client.CreateCustomer(customer)

	usageDate := time.Now().UTC()

	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)

	publicRepoId := stubs.GetRandomId64()
	_ = client.CreateRepo(publicRepoId, true)

	anotherPublicRepoId := stubs.GetRandomId64()
	_ = client.CreateRepo(anotherPublicRepoId, true)

	costCenterProto := stubs.CreateAzureCostCenterWithCustomerAndResources(customerId, []*proto.Resource{
		{
			Id:   fmt.Sprintf("%d", anotherPublicRepoId),
			Type: proto.ResourceType_Repo,
		},
	})
	_, _ = client.CreateCostCenter(costCenterProto)

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         publicRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	anotherEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         anotherPublicRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	// create usage in two public repos. one repo is in a cost center, the other is not.
	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", 10.0, usageDate, entity)
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", 5.0, usageDate, anotherEntity)
	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	allDiscountStates := client.GetAllDiscountStates(customerId, time.Now().UTC()).Discounts

	var publicRepoDiscountState *proto.DiscountState
	for _, discountState := range allDiscountStates {
		if discountState.Uuid == models.PublicRepo100PercentDiscountUUID {
			publicRepoDiscountState = discountState
			break
		}
	}

	// There should be 5 discount states: 4 SKU discounts from the customer's enterprise plan and the public repo discount
	g.Expect(len(allDiscountStates)).Should(gomega.Equal(7), "All discount states")
	g.Expect(publicRepoDiscountState).ShouldNot(gomega.BeNil(), "Public repo discount state")
	g.Expect(publicRepoDiscountState.Percentage).Should(gomega.Equal(100.0), "Public repo discount percentage")
	// 10 minutes (non cost center usage in a public repo) + 5 minutes (cost center usage in a public repo) = 15 minutes
	// 15 minutes * $0.008/minute for actions_linux = $0.12, which is 100% off, so the discount state amount should be $0.12
	g.Expect(publicRepoDiscountState.CurrentAmount).Should(gomega.Equal(.12), "Public repo discount current amount")
}

type monolithRepositoryAPIService struct {
	repos []*repositories.Repository
}

func (s *monolithRepositoryAPIService) GetRepositoryMetadata(ctx context.Context, req *repositories.GetRepositoryMetadataRequest) (*repositories.GetRepositoryMetadataResponse, error) {
	for _, r := range s.repos {
		if r.Id == req.Id {
			return &repositories.GetRepositoryMetadataResponse{
				Repository: r,
			}, nil
		}
	}

	return nil, fmt.Errorf("repository %d not found", req.Id)
}

func Test_Discount_Usage_Is_Free_For_Public_Repos(t *testing.T) {
	svc := &monolithRepositoryAPIService{
		repos: []*repositories.Repository{},
	}

	monolithServer := repositories.NewRepositoryAPIServer(svc)
	mockServer := httptest.NewServer(monolithServer)
	defer mockServer.Close()
	fmt.Printf("starting mock server %v, %v\n", monolithServer, mockServer.URL)

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	client.MonolithTwirpServerURL = mockServer.URL

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	publicRepoId := stubs.GetRandomId64()
	_ = client.CreateRepo(publicRepoId, true)

	privateRepoId := stubs.GetRandomId64()
	_ = client.CreateRepo(privateRepoId, false)

	uncachedPrivateRepoId := stubs.GetRandomId64()

	uncachedPublicRepoId := stubs.GetRandomId64()

	svc.repos = append(svc.repos, []*repositories.Repository{{
		Id:       uint64(uncachedPublicRepoId),
		IsPublic: true,
	}, {
		Id:       uint64(uncachedPrivateRepoId),
		IsPublic: false,
	}}...)

	quantity := 51_000.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	pricing := client.EnsureSpecificPricingExistsWithFreeForPublicRepos(0.008, "actions_linux", "actions", "Actions")

	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	publicRepoEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         publicRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	privateRepoEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         privateRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	uncachedPrivateRepoEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         uncachedPrivateRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	uncachedPublicRepoEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         uncachedPublicRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, publicRepoEntity)          // 100% discount because the repo is public
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, privateRepoEntity)         // full price since the repo is private
	usage3 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, uncachedPrivateRepoEntity) // full price since the repo is private not in DB
	usage4 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, uncachedPublicRepoEntity)  // 100% discount because the repo is public

	discountedUsages := []*hydroSchema.Usage{usage1, usage4}
	billableUsages := []*hydroSchema.Usage{usage2, usage3}
	var usages []*hydroSchema.Usage
	usages = append(usages, discountedUsages...)
	usages = append(usages, billableUsages...)
	usageCount := float64(len(usages))
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	u := client.GetUsageTotal("", pricing.Sku, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*usageCount), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(quantity*pricing.Price*usageCount), "usage Amount")

	now := time.Now()
	trackItems, _ := client.FetchDiscountTrackItems(customerId, models.PublicRepo100PercentDiscountUUID, now.Year(), int(now.Month()))
	g.Expect(len(trackItems)).Should(gomega.Equal(2), "public repo usage quantity")

	matchingOnIDs := func(id string) func(*models.DiscountTrackItem) bool {
		return func(item *models.DiscountTrackItem) bool {
			return item.Id == id
		}
	}
	g.Expect(trackItems).Should(a.IncludeItem(matchingOnIDs(usage1.UsageUuid)))

	uDiscount := client.GetDiscountTotal(pricing.Sku, customerId, usageDate, proto.BillingPeriod_Daily)
	var discountableQuantity float64
	for _, u := range discountedUsages {
		discountableQuantity += u.Quantity
	}
	discountableQuantity += 50000.0 // 50_000 discount from SKU
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(discountableQuantity), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(discountableQuantity*pricing.Price), "discount Amount")

	u = client.GetUsageTotal("", pricing.Sku, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*usageCount), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(quantity*pricing.Price*usageCount), "usage Amount")

	uDiscount = client.GetDiscountTotal(pricing.Sku, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(discountableQuantity), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(discountableQuantity*pricing.Price), "discount Amount")
}

func Test_Discount_Usage_Is_Not_Free_For_Public_Repos_For_Customer_With_Override(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Azure)
	customerProto.BillForPublicRepoUsage = true
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	publicRepoId := stubs.GetRandomId64()
	_ = client.CreateRepo(publicRepoId, true)

	privateRepoId := stubs.GetRandomId64()
	_ = client.CreateRepo(privateRepoId, false)

	quantity := 51_000.0
	usageDate := time.Date(2023, 7, 15, 3, 0, 0, 0, time.UTC)

	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	publicRepoEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         publicRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	privateRepoEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         privateRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", quantity, usageDate, publicRepoEntity)  // full price because the customer.BillForPublicRepoUsage is true
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", quantity, usageDate, privateRepoEntity) // full price since the repo is private

	usages := []*hydroSchema.Usage{usage1, usage2}
	usageCount := float64(len(usages))
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	actionsLinuxPrice := 0.008

	u := client.GetUsageTotal("", "actions_linux", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*usageCount), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(quantity*actionsLinuxPrice*usageCount), "usage Amount")

	now := time.Now()
	trackItems, _ := client.FetchDiscountTrackItems(customerId, models.PublicRepo100PercentDiscountUUID, now.Year(), int(now.Month()))
	g.Expect(len(trackItems)).Should(gomega.Equal(0), "public repo usage quantity")

	uDiscount := client.GetDiscountTotal("actions_linux", customerId, usageDate, proto.BillingPeriod_Daily)
	discountableQuantity := 50000.0 // 50_000 discount from SKU
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(discountableQuantity), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(discountableQuantity*actionsLinuxPrice), "discount Amount")

	u = client.GetUsageTotal("", "actions_linux", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*usageCount), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(quantity*actionsLinuxPrice*usageCount), "usage Amount")

	uDiscount = client.GetDiscountTotal("actions_linux", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(discountableQuantity), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(discountableQuantity*actionsLinuxPrice), "discount Amount")
}

func Test_Discount_Usage_Is_Not_Free_For_Public_Repos_For_Cost_Center_Customer_With_Override(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Azure)
	customerProto.BillForPublicRepoUsage = true
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	publicRepoId := stubs.GetRandomId64()
	privateRepoId := stubs.GetRandomId64()

	costCenterProto := stubs.CreateAzureCostCenterWithCustomerAndResources(customerId, []*proto.Resource{
		{
			Id:   fmt.Sprintf("%d", publicRepoId),
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   fmt.Sprintf("%d", privateRepoId),
			Type: proto.ResourceType_Repo,
		},
	})
	costCenterResp, _ := client.CreateCostCenter(costCenterProto)
	costCenterUuid := costCenterResp.CostCenter.CostCenterKey.Uuid

	_ = client.CreateRepo(publicRepoId, true)
	_ = client.CreateRepo(privateRepoId, false)

	quantity := 51_000.0
	usageDate := time.Date(2023, 7, 15, 3, 0, 0, 0, time.UTC)

	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	publicRepoEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         publicRepoId,
		ActorId:        stubs.GetRandomId64(),
	}
	privateRepoEntity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         privateRepoId,
		ActorId:        stubs.GetRandomId64(),
	}

	// full price because the repo belongs to cost center with enterprise customer.BillForPublicRepoUsage=true
	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", quantity, usageDate, publicRepoEntity)
	// full price because the repo is private
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", quantity, usageDate, privateRepoEntity)

	usages := []*hydroSchema.Usage{usage1, usage2}
	usageCount := float64(len(usages))
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	actionsLinuxPrice := 0.008

	u := client.GetUsageTotal("", "actions_linux", costCenterUuid, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*usageCount), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(quantity*actionsLinuxPrice*usageCount), "usage Amount")

	now := time.Now()
	trackItems, _ := client.FetchDiscountTrackItems(costCenterUuid, models.PublicRepo100PercentDiscountUUID, now.Year(), int(now.Month()))
	g.Expect(len(trackItems)).Should(gomega.Equal(0), "public repo usage quantity")

	uDiscount := client.GetDiscountTotal("actions_linux", costCenterUuid, usageDate, proto.BillingPeriod_Daily)
	discountableQuantity := 50000.0 // 50_000 discount from SKU
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(discountableQuantity), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(discountableQuantity*actionsLinuxPrice), "discount Amount")

	u = client.GetUsageTotal("", "actions_linux", costCenterUuid, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*usageCount), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(quantity*actionsLinuxPrice*usageCount), "usage Amount")

	uDiscount = client.GetDiscountTotal("actions_linux", costCenterUuid, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(discountableQuantity), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(discountableQuantity*actionsLinuxPrice), "discount Amount")
}

func Test_Discount_When_Plan_Discount_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	customerProto2 := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId2 := customerProto2.CustomerId
	_ = client.CreateCustomer(customerProto2)

	// Get pricing from hardcoded pricing list
	// Using skus in different targets to confirm the discount is not leaking between skus
	actionsLinux := "actions_linux"
	actionsStorage := "actions_storage"

	quantity := 25000.0 // 25k minutes from 50k discount
	storageQuantity := 1.0
	usageDate := time.Date(2023, 7, 15, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), actionsLinux, quantity, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), actionsLinux, quantity, customerId, usageDate)
	usage3 := stubs.CreateUsage(uuid.NewString(), actionsLinux, quantity, customerId, usageDate)
	usage4 := stubs.CreateUsage(uuid.NewString(), actionsStorage, storageQuantity, customerId, usageDate)
	usage5 := stubs.CreateUsage(uuid.NewString(), actionsStorage, storageQuantity, customerId, usageDate)
	usage6 := stubs.CreateUsage(uuid.NewString(), actionsLinux, quantity, customerId2, usageDate)
	usage7 := stubs.CreateUsage(uuid.NewString(), actionsStorage, storageQuantity, customerId2, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6, usage7}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	u := client.GetUsageTotal("", actionsLinux, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*3), "actions_linux usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(600.0), "actions_linux usage amount")

	uDiscount := client.GetDiscountTotal(actionsLinux, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(50000.0), "actions_linux discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(400.0), "actions_linux discount amount")

	u = client.GetUsageTotal("", actionsLinux, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*3), "actions_linux usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(600.0), "actions_linux usage amount")

	uDiscount = client.GetDiscountTotal(actionsLinux, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(50000.0), "actions_linux discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(400.0), "actions_linux discount amount")

	uLinux2 := client.GetUsageTotal("", actionsLinux, customerId2, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(uLinux2.Quantity)).Should(gomega.Equal(quantity), "actions_linux usage quantity")
	g.Expect(float64(uLinux2.BillableAmount)).Should(gomega.Equal(200.0), "actions_linux usage amount")

	uLinuxDiscount2 := client.GetDiscountTotal(actionsLinux, customerId2, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(uLinuxDiscount2.Quantity)).Should(gomega.Equal(25000.0), "actions_linux discount quantity")
	g.Expect(float64(uLinuxDiscount2.DiscountAmount)).Should(gomega.Equal(200.0), "actions_linux discount amount")
}

func Test_Discount_Get_DiscountLineItems(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	sku := "first-sku"
	price := 20.0
	pricing := client.EnsureSpecificPricingExists(price, sku, "actions", "Actions")
	quantity := 1.0

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()
	discount := stubs.CreatePercentageDiscount(
		customerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing.Sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		10.0,
		yesterday,
		nextYear,
	)

	discountResponse, err := client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount")
	g.Expect(discountResponse.Uuid).ShouldNot(gomega.BeNil())

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerId, usageDate)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerId, usageDate.Add(time.Hour*48))

	usages := []*hydroSchema.Usage{usage1, usage2, usage3}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Daily).BillingItems
	g.Expect(len(u)).Should(gomega.Equal(1), "daily line items")
	g.Expect(float64(u[0].Quantity)).Should(gomega.Equal(2.0), "daily usage quantity")
	g.Expect(float64(u[0].BilledAmount)).Should(gomega.Equal(40.0), "daily usage Amount")

	d := client.GetDiscountLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Daily).DiscountItems
	g.Expect(len(d)).Should(gomega.Equal(1), "daily discount items")
	g.Expect(float64(d[0].Quantity)).Should(gomega.Equal(0.2), "daily discount quantity")
	g.Expect(float64(d[0].DiscountAmount)).Should(gomega.Equal(4.0), "daily discount Amount")

	netUsage := client.GetNetUsageLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Daily).NetUsageItems
	g.Expect(len(netUsage)).Should(gomega.Equal(1), "number of daily net usage items")
	g.Expect(float64(netUsage[0].Quantity)).Should(gomega.Equal(2.0), "daily net usage quantity")
	g.Expect(float64(netUsage[0].DiscountAmount)).Should(gomega.Equal(4.0), "daily discount Amount")
	g.Expect(float64(netUsage[0].NetAmount)).Should(gomega.Equal(36.0), "daily net amount")

	client.RunMonthlyJob(len(usages))

	u = client.GetUsageLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Monthly).BillingItems
	g.Expect(len(u)).Should(gomega.Equal(2), "monthly line items")
	g.Expect(u).Should(a.IncludeItem(func(d *proto.BillingItem) bool {
		return d.Quantity == 2.0 && d.BilledAmount == 40.0
	}), "monthly usage quantity first day")
	g.Expect(u).Should(a.IncludeItem(func(d *proto.BillingItem) bool {
		return d.Quantity == 1.0 && d.BilledAmount == 20.0
	}), "monthly usage quantity 2nd day")

	d = client.GetDiscountLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Monthly).DiscountItems
	g.Expect(len(d)).Should(gomega.Equal(2), "monthly discount items")
	g.Expect(d).Should(a.IncludeItem(func(d *proto.DiscountItem) bool {
		return d.Quantity == 0.2 && d.DiscountAmount == 4.0
	}), "monthly usage quantity first day")
	g.Expect(d).Should(a.IncludeItem(func(d *proto.DiscountItem) bool {
		return d.Quantity == 0.1 && d.DiscountAmount == 2.0
	}), "monthly usage quantity 2nd day")

	// ensure we don't return discount line items when querying for an org or repo because we don't have discount data for these queries
	d = client.GetDiscountLineItemsWithOrgOrRepo("", sku, customerId, usageDate, proto.BillingPeriod_Monthly, 0, 1).DiscountItems
	g.Expect(len(d)).Should(gomega.Equal(0), "monthly discount items when requesting usage for a repo")

	netUsage = client.GetNetUsageLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Monthly).NetUsageItems
	fmt.Println(netUsage)
	g.Expect(len(netUsage)).Should(gomega.Equal(2), "monthly line items")
	g.Expect(netUsage).Should(a.IncludeItem(func(d *proto.NetUsageItem) bool {
		return d.Quantity == 2.0 && d.GrossAmount == 40.0
	}), "monthly usage quantity first month")
	g.Expect(netUsage).Should(a.IncludeItem(func(d *proto.NetUsageItem) bool {
		return d.Quantity == 1.0 && d.GrossAmount == 20.0
	}), "monthly usage quantity 2nd month")
	g.Expect(netUsage).Should(a.IncludeItem(func(d *proto.NetUsageItem) bool {
		return d.NetAmount == 36.0 && d.DiscountAmount == 4.0
	}), "monthly usage with discount month")
	g.Expect(netUsage).Should(a.IncludeItem(func(d *proto.NetUsageItem) bool {
		return d.NetAmount == 18.0 && d.DiscountAmount == 2.0
	}), "monthly usage with discount 2nd month")

	client.RunYearlyJob(len(usages))

	u = client.GetUsageLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Yearly).BillingItems
	g.Expect(len(u)).Should(gomega.Equal(1), "yearly line items")
	g.Expect(u).Should(a.IncludeItem(func(d *proto.BillingItem) bool {
		return d.Quantity == 3 && d.BilledAmount == 60.0
	}), "yearly usage quantity first day")

	d = client.GetDiscountLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Yearly).DiscountItems
	g.Expect(len(d)).Should(gomega.Equal(1), "yearly discount items")
	g.Expect(d).Should(a.IncludeItem(func(d *proto.DiscountItem) bool {
		return d.Quantity == 0.3 && d.DiscountAmount == 6.0
	}), "yearly usage quantity first day")

	// ensure we don't return discount line items when querying for an org or repo because we don't have discount data for these queries
	d = client.GetDiscountLineItemsWithOrgOrRepo("", sku, customerId, usageDate, proto.BillingPeriod_Yearly, 1, 0).DiscountItems
	g.Expect(len(d)).Should(gomega.Equal(0), "yearly discount items when requesting usage for an org")

	netUsage = client.GetNetUsageLineItems("", sku, customerId, usageDate, proto.BillingPeriod_Yearly).NetUsageItems
	g.Expect(len(netUsage)).Should(gomega.Equal(1), "yearly line items")
	g.Expect(netUsage).Should(a.IncludeItem(func(d *proto.NetUsageItem) bool {
		return d.Quantity == 3 && d.GrossAmount == 60.0
	}), "yearly usage quantity")
	g.Expect(netUsage).Should(a.IncludeItem(func(d *proto.NetUsageItem) bool {
		return d.NetAmount == 54.0 && d.DiscountAmount == 6.0
	}), "yearly usage with discount")
}

func Test_Discount_Cost_Center_Shares_Parent_Customer_Plan_Discount(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	_ = client.CreateCustomer(customerProto)

	resourceId := stubs.GetRandomId64()
	costCenterProto := stubs.CreateZuoraCostCenterWithCustomerAndResources(customerId, []*proto.Resource{
		{
			Id:   fmt.Sprintf("%d", resourceId),
			Type: proto.ResourceType_Repo,
		},
	})
	response, _ := client.CreateCostCenter(costCenterProto)
	costCenterUuid := response.CostCenter.CostCenterKey.Uuid

	usageDate := time.Date(2023, 7, 15, 3, 0, 0, 0, time.UTC)
	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         resourceId,
		ActorId:        stubs.GetRandomId64(),
	}

	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", 35_000.0, usageDate, entity)
	usage2 := stubs.CreateUsage(uuid.NewString(), "actions_linux", 15_000.0, customerId, usageDate)

	usage3 := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux", 10_000.0, usageDate, entity)
	usage4 := stubs.CreateUsage(uuid.NewString(), "actions_linux", 100.0, customerId, usageDate)

	// these usages should consume all of the enterprise customer's plan discount
	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// these usages should not qualify for anymore discounts
	usages = []*hydroSchema.Usage{usage3, usage4}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	actionsStandardDiscountUuid := "85679075-fe74-461e-9c22-808ac1393944"

	// check cost center usage and discounts
	u := client.GetUsageTotal("", "actions_linux", costCenterUuid, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(35_000.0+10_000.0), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(360.0), "usage Amount")

	uDiscount := client.GetDiscountTotal("actions_linux", costCenterUuid, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(35_000.0), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(35_000*0.008), "discount Amount")

	u = client.GetUsageTotal("", "actions_linux", costCenterUuid, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(35_000.0+10_000.0), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(360.0), "usage Amount")

	uDiscount = client.GetDiscountTotal("actions_linux", costCenterUuid, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(35_000.0), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(35_000*0.008), "discount Amount")

	// cost center's plan discountState should be tracked under the enterprise customer's discountState
	ds := client.GetDiscountState(costCenterUuid, actionsStandardDiscountUuid, time.Now().UTC())
	g.Expect(ds.DiscountState).Should(gomega.BeNil(), "discount state")

	allDiscountStates := client.GetAllDiscountStates(costCenterUuid, time.Now().UTC()).Discounts
	g.Expect(len(allDiscountStates)).Should(gomega.Equal(0), "all discount states")

	// check parent customer usage and discounts
	u = client.GetUsageTotal("", "actions_linux", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(15_000.0+100.0), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(120.8), "usage Amount")

	uDiscount = client.GetDiscountTotal("actions_linux", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(15_000.0), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(15_000.0*0.008), "discount Amount")

	u = client.GetUsageTotal("", "actions_linux", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(15_000.0+1_00.0), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(120.8), "usage Amount")

	uDiscount = client.GetDiscountTotal("actions_linux", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(uDiscount.Quantity)).Should(gomega.Equal(15_000.0), "discount quantity")
	g.Expect(float64(uDiscount.DiscountAmount)).Should(gomega.Equal(15_000.0*0.008), "discount Amount")

	// enterprise customer's plan discount should be fully applied
	ds = client.GetDiscountState(customerId, actionsStandardDiscountUuid, time.Now().UTC())
	g.Expect(ds.DiscountState.IsFullyApplied).Should(gomega.BeTrue(), "enterprise discount IsFullyApplied")
	g.Expect(ds.DiscountState.CurrentAmount).Should(gomega.Equal(400.0), "enterprise discount CurrentAmount")

	allDiscountStates = client.GetAllDiscountStates(customerId, time.Now().UTC()).Discounts
	g.Expect(len(allDiscountStates)).Should(gomega.Equal(6), "enterprise all discount states")
	g.Expect(allDiscountStates[0].IsFullyApplied).Should(gomega.BeTrue(), "enterprise all discount states IsFullyApplied")
	g.Expect(allDiscountStates[0].CurrentAmount).Should(gomega.Equal(400.0), "enterprise all discount states CurrentAmount")
	g.Expect(allDiscountStates[0].Uuid).Should(gomega.Equal(actionsStandardDiscountUuid), "enterprise all discount states uuid")
}

func Test_Discount_ByOrgRepoProductSKU_Discount_Rollups(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDateOne := time.Date(2023, 7, 15, 3, 0, 0, 0, time.UTC)
	usageDateTwo := time.Date(2023, 7, 16, 5, 0, 0, 0, time.UTC)
	usageDateThree := time.Date(2023, 7, 25, 7, 0, 0, 0, time.UTC)

	repoOneId := stubs.GetRandomId64()
	repoTwoId := stubs.GetRandomId64()
	orgOneId := stubs.GetRandomId64()

	usage1 := stubs.CreateUsageWithOrgRepo("actions_linux", 15_000.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage2 := stubs.CreateUsageWithOrgRepo("actions_linux", 100.0, customerId, usageDateTwo, repoTwoId, orgOneId)
	// no discounts for this SKU
	usage3 := stubs.CreateUsageWithOrgRepo("actions_linux_16_core", 100.0, customerId, usageDateTwo, repoTwoId, orgOneId)
	// note that this item has a different usage data but still somehow gets rolled up into the same line item from different date
	// but with the same org, repo, product SKU pairing
	usage4 := stubs.CreateUsageWithOrgRepo("actions_linux", 100.0, customerId, usageDateThree, repoTwoId, orgOneId)
	usage5 := stubs.CreateUsageWithOrgRepo("actions_linux", 100.0, customerId, usageDateThree, repoTwoId, orgOneId)
	usage6 := stubs.CreateUsageWithOrgRepo("actions_macos", 100.0, customerId, usageDateThree, repoTwoId, orgOneId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))
	client.RunYearlyJob(len(usages))

	// query and compare monthly usage and discount rollups
	usageLineItems := client.GetUsageLineItemsGroupBy("", "", customerId, usageDateOne, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupByOrgRepoProductSku).BillingItems
	g.Expect(len(usageLineItems)).Should(gomega.Equal(5), "number of monthly usage line items")

	discountLineItems := client.GetDiscountLineItemsGroupBy("", "", customerId, usageDateOne, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupByOrgRepoProductSku).DiscountItems
	g.Expect(len(discountLineItems)).Should(gomega.Equal(4), "number of monthly discount line items")

	sumDiscountQuantity := 0.0
	for _, d := range discountLineItems {
		sumDiscountQuantity += d.Quantity
	}
	g.Expect(sumDiscountQuantity).Should(gomega.Equal(15_400.0), "monthly discount amount")

	// should include all the actions linux usage discounts (100 less than the above total due to actions_macos)
	discountTotal := client.GetDiscountTotal("actions_linux", customerId, usageDateOne, proto.BillingPeriod_Monthly)
	g.Expect(float64(discountTotal.Quantity)).Should(gomega.Equal(15_300.0), "discount quantity")
}
