package engines

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_FindBudgetsFor_EmptyEntityDetail_ReturnsNoErrorAndEmptyBudgets(t *testing.T) {
	t.Skip("Skipping test, possibly outdated")

	c, telem, stats, logger, db := helpers.SetupMocks(t)
	cfg := &config.Config{
		Environment: "test",
	}

	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	var budgets []*models.Budget

	budgets = append(budgets, &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "customer:1:budgets:repository:199:product:copilot",
				PartitionKey: "customer:1:budgets",
			},
			TargetType: models.Repository,
			TargetId:   "199",
		},
		TargetAmount:    200,
		BudgetLimitType: models.StopActiveUsage,
	})

	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		c.NewQueryItemsPager(
			pegomock.Eq("SELECT * FROM c"),
			pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:budgets")),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(pager)

	fakeVexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)

	engineParams := &EngineParams{
		db:             db,
		cfg:            cfg,
		aqueductClient: nil,
		statter:        stats,
		tracer:         telem.Tracer.Tracer,
		flagger:        fakeVexiClient,
	}

	e := &models.EntityDetail{
		CostCenterDetail: &models.CostCenterDetail{},
	}
	customerEngine := fakes.NewMockCustomerEngineInterface()
	eng := NewBudgetEngine(engineParams, customerEngine)
	b, error := eng.FindBudgetsFor(context.Background(), logger, "sku1", "skuString", e, 2019, 4)
	assert.Nil(t, error)
	assert.Equal(t, 0, len(b))
	c.VerifyWasCalled(pegomock.Times(6)).ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())
}

func Test_FindBudgetsFor_EntityDetailWithActorId_Returns1BudgetForUser(t *testing.T) {
	t.Skip("Skipping test, possibly outdated, there isnt a way to set budgets per actor")
	c, telem, stats, logger, db := helpers.SetupMocks(t)

	cfg := &config.Config{
		Environment: "test",
	}

	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	uBudget := &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "customer:100:budgets:user:1:product:actions",
				PartitionKey: "customer:100:budgets",
			},
			TargetType: models.User,
			TargetId:   "1",
		},
		TargetAmount:    200,
		BudgetLimitType: models.StopActiveUsage,
	}
	// Return a budget for the actor
	// Budget quereies query the `customer:<customer_id>:budgets` partition along with
	// a combination of `product/sku`  and `customer/enterprise` IDs.
	var budgets []*models.Budget
	err := helpers.ReadFixture("fixtures/budgets_non_gh.json", &budgets)
	assert.NoError(t, err)
	// make fake budget data
	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		c.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	engineParams := &EngineParams{
		db:             db,
		cfg:            cfg,
		aqueductClient: nil,
		statter:        stats,
		tracer:         telem.Tracer.Tracer,
	}

	e := &models.EntityDetail{
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "100",
		},
		ActorId: 1,
	}
	customerEngine := fakes.NewMockCustomerEngineInterface()

	eng := NewBudgetEngine(engineParams, customerEngine)
	b, error := eng.FindBudgetsFor(context.Background(), logger, "actions", "actions-linux", e, 2019, 4)

	assert.Nil(t, error)
	assert.Equal(t, 1, len(b))
	assert.Equal(t, uBudget, b[0])
	c.VerifyWasCalled(pegomock.Times(9)).ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:100:budgets")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())
}

func Test_FindBudgetsFor_EntityDetailWithActorIdAndGitHubOwned_Returns1BudgetForUser(t *testing.T) {
	c, telem, stats, logger, db := helpers.SetupMocks(t)
	now := models.UTCNow()
	year := int64(now.Year())
	month := int64(now.Month())

	cfg := &config.Config{
		Environment: "test",
	}

	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	budget, _ := StubBudgetReadItemResponseWithType(t, 1061737, "actions", 1, models.User, 1000, "deadbeef")
	// make fake budget data
	pager := helpers.MakePagerWithData(t, []*models.Budget{budget})

	pegomock.When(
		c.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	engineParams := &EngineParams{
		db:             db,
		cfg:            cfg,
		aqueductClient: nil,
		statter:        stats,
		tracer:         telem.Tracer.Tracer,
	}

	e := &models.EntityDetail{
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "1061737",
		},
		ActorId: 1,
	}

	customerEngine := fakes.NewMockCustomerEngineInterface()
	eng := NewBudgetEngine(engineParams, customerEngine)
	b, error := eng.FindBudgetsFor(context.Background(), logger, "actions", "actions-linux", e, year, month)

	assert.Nil(t, error)
	assert.Equal(t, 1, len(b))
}

func Test_FindBudgetsFor_EntityDetailWithCostCenter_Returns1BudgetForCustomer(t *testing.T) {
	c, telem, stats, logger, db := helpers.SetupMocks(t)
	now := models.UTCNow()
	year := int64(now.Year())
	month := int64(now.Month())

	cfg := &config.Config{
		Environment: "test",
	}

	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	uBudget := &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "customer:100:budgets:customer:100:product:actions",
				PartitionKey: "customer:100:budgets",
			},
			CustomerId:        "100",
			TargetId:          "100",
			TargetType:        models.CustomerResource,
			PricingTargetType: models.ProductPricing,
			PricingTargetId:   "actions",
		},
		TargetAmount:   models.ToWholeAmount[uint64](10),
		Uuid:           "helloworld",
		BudgetAlerting: &models.BudgetAlerting{},
	}

	budget, _ := StubBudgetReadItemResponseWithType(t, 100, "actions", 100, models.CustomerResource, 10, "helloworld")
	// make fake budget data
	pager := helpers.MakePagerWithData(t, []*models.Budget{budget})

	pegomock.When(
		c.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	engineParams := &EngineParams{
		db:             db,
		cfg:            cfg,
		aqueductClient: nil,
		statter:        stats,
		tracer:         telem.Tracer.Tracer,
	}

	e := &models.EntityDetail{
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "100",
		},
		// replicate the enterprise customer ID being sent to a cost center ID
		CustomerId: "100-200-300-400-500",
	}
	customerEngine := fakes.NewMockCustomerEngineInterface()

	eng := NewBudgetEngine(engineParams, customerEngine)
	b, error := eng.FindBudgetsFor(context.Background(), logger, "actions", "actions-linux", e, year, month)

	assert.Nil(t, error)
	assert.Equal(t, 1, len(b))
	assert.Equal(t, uBudget, b[0])
}

func Test_BudgetsWithFixtures_LegacyFindBudgetsFor_non_gh_Fixtures(t *testing.T) {

	c, telem, stats, logger, db := helpers.SetupMocks(t)
	now := models.UTCNow()
	year := int64(now.Year())
	month := int64(now.Month())

	cfg := &config.Config{
		Environment: "test",
	}

	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)

	var budgets []*models.Budget
	err := helpers.ReadFixture("fixtures/budgets_non_gh.json", &budgets)
	assert.NoError(t, err)
	// make fake budget data
	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		c.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	e := &models.EntityDetail{
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "278832",
			CostCenterUUID:       "ac37e12b-0fbf-43ce-a993-1c6ee63bcafa",
		},
		CustomerId:     "278832",
		OrganizationId: 139111664, // these are shared in the fixtures for gh and non_gh budgets
		RepositoryId:   839259262, // these are shared in the fixtures for gh and non_gh budgets
	}

	engineParams := &EngineParams{
		db:             db,
		cfg:            cfg,
		aqueductClient: nil,
		statter:        stats,
		tracer:         telem.Tracer.Tracer,
	}

	customerEngine := fakes.NewMockCustomerEngineInterface()
	eng := NewBudgetEngine(engineParams, customerEngine)
	b, error := eng.FindBudgetsFor(context.Background(), logger, "actions", "actions-linux", e, year, month)

	assert.Nil(t, error)
	assert.Equal(t, 3, len(b))
}

func Test_BudgetsWithFixtures_FindBudgetsFor_ghFixtures(t *testing.T) {
	c, telem, stats, logger, db := helpers.SetupMocks(t)
	now := models.UTCNow()
	year := int64(now.Year())
	month := int64(now.Month())

	cfg := &config.Config{
		Environment: "test",
	}

	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	var budgets []*models.Budget
	err := helpers.ReadFixture("fixtures/budgets_gh.json", &budgets)
	assert.NoError(t, err)
	// make fake budget data
	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		c.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	// The fixtures have these values for the entity detail
	e := &models.EntityDetail{
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "1061737",
			CostCenterUUID:       "ac37e12b-0fbf-43ce-a993-1c6ee63bcafa",
		},
		CustomerId:     "1061737",
		OrganizationId: 139111664, // these are shared in the fixtures for gh and non_gh budgets
		RepositoryId:   839259262, // these are shared in the fixtures for gh and non_gh budgets
	}

	engineParams := &EngineParams{
		db:             db,
		cfg:            cfg,
		aqueductClient: nil,
		statter:        stats,
		tracer:         telem.Tracer.Tracer,
	}

	customerEngine := fakes.NewMockCustomerEngineInterface()
	eng := NewBudgetEngine(engineParams, customerEngine)
	b, error := eng.FindBudgetsFor(context.Background(), logger, "actions", "actions-linux", e, year, month)

	assert.Nil(t, error)
	assert.Equal(t, 3, len(b))
}

func MockBudgetPointReadsFromFixture(f, p, sku string, c *fakes.MockCosmosConnection, t *testing.T) {
	b := make([]*models.Budget, 0)
	err := helpers.ReadFixture(f, &b)
	assert.NoError(t, err)

	for _, i := range b {
		ar := helpers.MockAzureItemResponse(t, i)
		pegomock.When(c.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(i.PartitionKey)),
			pegomock.Eq(i.Id),
			pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(ar, nil)

		// regex to match the :product:* part of the id
		r := regexp.MustCompile(`(:product:.*)`)
		e := regexp.MustCompile(`customer:(\d+):budgets:`)
		// discard :product:actions part to ignore the non-pricing id for the budget
		nonPricingId := r.ReplaceAllString(i.Id, "")
		// discard :sku:actions part to ignore the non-sku id for the budget
		skuBudgetsId := r.ReplaceAllString(i.Id, fmt.Sprintf(":sku:%s", sku))
		// discard enterprise budgets for now, since the fixtures don't have them
		// extract the matched id from the regex
		id := e.FindStringSubmatch(i.Id)[1]
		enterpriseBudgetsIDs := []string{
			e.FindString(i.Id) + "enterprise:" + string(id),
			e.FindString(i.Id) + "enterprise:" + string(id) + ":product:" + p,
			e.FindString(i.Id) + "enterprise:" + string(id) + ":sku:" + sku,
		}
		// These are the expected reads for a user budget. We're going to return 404 for all of them
		pegomock.When(c.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(i.PartitionKey)),
			pegomock.Eq(nonPricingId),
			pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(helpers.MockAzureItemResponseWith404(t), &azcore.ResponseError{StatusCode: http.StatusNotFound})

		pegomock.When(c.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(i.PartitionKey)),
			pegomock.Eq(skuBudgetsId),
			pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(helpers.MockAzureItemResponseWith404(t), &azcore.ResponseError{StatusCode: http.StatusNotFound})

		for _, j := range enterpriseBudgetsIDs {
			pegomock.When(c.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Eq(azcosmos.NewPartitionKeyString(i.PartitionKey)),
				pegomock.Eq(j),
				pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(helpers.MockAzureItemResponseWith404(t), &azcore.ResponseError{StatusCode: http.StatusNotFound})
		}

	}

}

func StubBudgetReadItemResponseWithType(t *testing.T, customerId int64, product string, targetId int64, targetType models.ResourceType, targetAmount float64, uuid string) (*models.Budget, azcosmos.ItemResponse) {
	var keyId string
	switch targetType {
	case models.User:
		keyId = fmt.Sprintf("user:%d:product:%s", targetId, product)
	case models.OwningEntity:
		keyId = fmt.Sprintf("owning_entity:%d:product:%s", targetId, product)
	case models.Enterprise:
		keyId = fmt.Sprintf("enterprise:%d:product:%s", targetId, product)
	case models.Repository:
		keyId = fmt.Sprintf("repository:%d:product:%s", targetId, product)
	case models.CostCenterResource:
		keyId = fmt.Sprintf("cost_center:%d:product:%s", targetId, product)
	case models.CustomerResource:
		keyId = fmt.Sprintf("customer:%d:product:%s", targetId, product)
	}
	budget := &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           fmt.Sprintf("customer:%d:budgets:%s", customerId, keyId),
				PartitionKey: fmt.Sprintf("customer:%d:budgets", customerId),
			},
			CustomerId:        fmt.Sprintf("%d", customerId),
			TargetId:          fmt.Sprintf("%d", targetId),
			TargetType:        targetType,
			PricingTargetType: models.ProductPricing,
			PricingTargetId:   product,
		},
		TargetAmount:   models.ToWholeAmount[uint64](targetAmount),
		Uuid:           uuid,
		BudgetAlerting: &models.BudgetAlerting{},
	}

	return budget, helpers.MockAzureItemResponse(t, budget)
}
