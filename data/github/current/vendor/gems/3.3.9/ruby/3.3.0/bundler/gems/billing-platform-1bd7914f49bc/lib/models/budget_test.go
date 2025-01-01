package models

import (
	"fmt"
	"reflect"
	"testing"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/stubs"

	"github.com/onsi/gomega"
)

func Test_NewBudget(t *testing.T) {

	customerId := stubs.GetRandomId64AsString()
	targetId := stubs.GetRandomId64AsString()
	userId := stubs.GetRandomId64AsString()

	protoBudget := &proto.Budget{
		Key: &proto.BudgetKey{
			CustomerId: customerId,
			TargetType: proto.ResourceType_Enterprise,
			TargetId:   targetId,
		},
		TargetAmount: 100,
		BudgetAlerting: &proto.BudgetAlerting{
			WillAlert:        true,
			RecipientUserIds: []string{userId},
		},
	}
	b, err := NewBudget(protoBudget)

	if err != nil {
		t.Error("NewBudget should not return an error", err)
		t.Fail()
	}

	if b.Uuid == "" {
		t.Error("Uuid should be present")
		t.Fail()
	}
	if b.CustomerId != customerId {
		t.Error("CustomerId should be ", customerId)
		t.Fail()
	}
	if b.TargetId != targetId {
		t.Error("TargetId should be ", targetId)
		t.Fail()
	}
	if b.TargetType != Enterprise {
		t.Error("TargetType should be Enterprise")
		t.Fail()
	}
	if b.TargetAmount != uint64(NanoHundred) {
		t.Error("TargetAmount should be NanoHundred", b.TargetAmount)
		t.Fail()
	}
	if b.BudgetAlerting.WillAlert != true {
		t.Error("BudgetAlerting.WillAlert should be true")
		t.Fail()
	}
	if !reflect.DeepEqual(b.BudgetAlerting.RecipientUserIDs, []string{userId}) {
		t.Error("BudgetAlerting.RecipientUserIds should be [", userId, "]")
		t.Fail()
	}

	key := b
	extractedPartitionKey := fmt.Sprintf("customer:%s:budgets", customerId)
	if key.PartitionKey != extractedPartitionKey {
		t.Error("PartitionKey should be", extractedPartitionKey, "but was", key.PartitionKey)
		t.Fail()
	}
	extractedId := fmt.Sprintf("customer:%s:budgets:enterprise:%s", customerId, targetId)
	if key.Id != extractedId {
		t.Error("Id should be", extractedId, "but was", key.Id)
		t.Fail()
	}
}

func Test_NewBudget_withProduct(t *testing.T) {

	customerId := stubs.GetRandomId64AsString()
	targetId := stubs.GetRandomId64AsString()
	userId := stubs.GetRandomId64AsString()
	product := "ProductTObudgetOn"

	protoBudget := &proto.Budget{
		Key: &proto.BudgetKey{
			CustomerId:        customerId,
			TargetType:        proto.ResourceType_Enterprise,
			TargetId:          targetId,
			PricingTargetType: proto.PricingTargetType_ProductPricing,
			PricingTargetId:   product,
		},
		TargetAmount: 100,
		BudgetAlerting: &proto.BudgetAlerting{
			WillAlert:        true,
			RecipientUserIds: []string{userId},
		},
	}
	b, _ := NewBudget(protoBudget)

	if b.CustomerId != customerId {
		t.Error("CustomerId should be ", customerId)
		t.Fail()
	}
	if b.TargetId != targetId {
		t.Error("TargetId should be ", targetId)
		t.Fail()
	}
	if b.TargetType != Enterprise {
		t.Error("TargetType should be Enterprise")
		t.Fail()
	}
	if b.TargetAmount != uint64(NanoHundred) {
		t.Error("TargetAmount should be 10000000", b.TargetAmount)
		t.Fail()
	}
	if b.PricingTargetId != "ProductTObudgetOn" {
		t.Error("Product should be ProductTObudgetOn")
		t.Fail()
	}

	key := b
	extractedPartitionKey := fmt.Sprintf("customer:%s:budgets", customerId)
	if key.PartitionKey != extractedPartitionKey {
		t.Error("PartitionKey should be", extractedPartitionKey, "but was", key.PartitionKey)
		t.Fail()
	}
	extractedId := fmt.Sprintf("customer:%s:budgets:enterprise:%s:product:%s", customerId, targetId, product)
	if key.Id != extractedId {
		t.Error("Id should be", extractedId, "but was", key.Id)
		t.Fail()
	}
}

func Test_NewBudgetStateKey(t *testing.T) {

	customerId := stubs.GetRandomId64AsString()
	targetId := stubs.GetRandomId64AsString()
	id := "someid"

	protoKey := &proto.BudgetKey{
		CustomerId: customerId,
		TargetType: proto.ResourceType_Enterprise,
		TargetId:   targetId,
	}

	budgetKey := NewBudgetKey(protoKey)

	b := budgetKey.ToBudgetStateKey(2019, 1, id)

	extractedPartitionKey := fmt.Sprintf("customer:%s:budgets:enterprise:%s:2019:1", customerId, targetId)
	if b.PartitionKey != extractedPartitionKey {
		t.Error("PartitionKey should be", extractedPartitionKey, "but was", b.PartitionKey)
		t.Fail()
	}
	if b.Id != id {
		t.Error("Id should be", id, "but was", b.Id)
		t.Fail()
	}
}

func Test_NewBudgetKey(t *testing.T) {
	customerId := stubs.GetRandomId64AsString()
	targetId := stubs.GetRandomId64AsString()

	protoKey := &proto.BudgetKey{
		CustomerId: customerId,
		TargetType: proto.ResourceType_Enterprise,
		TargetId:   targetId,
	}

	b := NewBudgetKey(protoKey)

	if b.CustomerId != customerId {
		t.Error("CustomerId should be ", customerId)
		t.Fail()
	}
	if b.TargetId != targetId {
		t.Error("TargetId should be ", targetId)
		t.Fail()
	}
	if b.TargetType != Enterprise {
		t.Error("TargetType should be Enterprise")
		t.Fail()
	}

	key := b
	extractedPartitionKey := fmt.Sprintf("customer:%s:budgets", customerId)
	if key.PartitionKey != extractedPartitionKey {
		t.Error("PartitionKey should be", extractedPartitionKey, "but was", key.PartitionKey)
		t.Fail()
	}
	extractedId := fmt.Sprintf("customer:%s:budgets:enterprise:%s", customerId, targetId)
	if key.Id != extractedId {
		t.Error("Id should be", extractedId, "but was", key.Id)
		t.Fail()
	}
}

func Test_NewBudgetState(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	budget := Budget{
		BudgetKey: &BudgetKey{
			Key: &Key{Id: "budgetId", PartitionKey: "budgetPartitionKey"},
		},
		TargetAmount:    100,
		BudgetLimitType: PreventFurtherUsage,
	}

	budgetState := NewBudgetState(&budget, 2024, 5)
	g.Expect(budgetState.Key.PartitionKey).To(gomega.Equal("budgetId:2024:5"))
	g.Expect(budgetState.Key.Id).To(gomega.Equal("budgetState"))
	g.Expect(budgetState.Quantity).To(gomega.Equal(int64(0)))
	g.Expect(budgetState.CurrentAmount).To(gomega.Equal(uint64(0)))
	g.Expect(budgetState.TargetAmount).To(gomega.Equal(uint64(100)))
	g.Expect(budgetState.IsFullyFunded).To(gomega.Equal(false))
}

func Test_CalculateOverage_ZeroOverage(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	budget := Budget{
		BudgetKey: &BudgetKey{
			Key: &Key{Id: "budgetId", PartitionKey: "budgetPartitionKey"},
		},
		TargetAmount:    100,
		BudgetLimitType: PreventFurtherUsage,
	}

	budgetState := BudgetState{
		Key:           &Key{Id: DocumentIdBudgetState, PartitionKey: "budgetId:2024:5"},
		CurrentAmount: 90,
		TargetAmount:  100,
		Quantity:      90,
	}

	overageAmount := budgetState.CalculateOverage(budget, 10)
	g.Expect(overageAmount).To(gomega.Equal(int64(0)))
}

func Test_CalculateOverage_BudgetRemaining(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	budget := Budget{
		BudgetKey: &BudgetKey{
			Key: &Key{Id: "budgetId", PartitionKey: "budgetPartitionKey"},
		},
		TargetAmount:    100,
		BudgetLimitType: PreventFurtherUsage,
	}

	budgetState := BudgetState{
		Key:           &Key{Id: DocumentIdBudgetState, PartitionKey: "budgetId:2024:5"},
		CurrentAmount: 10,
		TargetAmount:  100,
		Quantity:      10,
	}

	overageAmount := budgetState.CalculateOverage(budget, 10)
	g.Expect(overageAmount).To(gomega.Equal(int64(0)))
}

func Test_CalculateOverage_WithOverage(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	budget := Budget{
		BudgetKey: &BudgetKey{
			Key: &Key{Id: "budgetId", PartitionKey: "budgetPartitionKey"},
		},
		TargetAmount:    100,
		BudgetLimitType: PreventFurtherUsage,
	}

	budgetState := BudgetState{
		Key:           &Key{Id: DocumentIdBudgetState, PartitionKey: "budgetId:2024:5"},
		CurrentAmount: 99,
		TargetAmount:  100,
		Quantity:      99,
	}

	overageAmount := budgetState.CalculateOverage(budget, 10)
	g.Expect(overageAmount).To(gomega.Equal(int64(9)))
}

func Test_CalculateOverage_AlertingOnly(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	budget := Budget{
		BudgetKey: &BudgetKey{
			Key: &Key{Id: "budgetId", PartitionKey: "budgetPartitionKey"},
		},
		TargetAmount:    100,
		BudgetLimitType: AlertingOnly,
	}

	budgetState := BudgetState{
		Key:           &Key{Id: DocumentIdBudgetState, PartitionKey: "budgetId:2024:5"},
		CurrentAmount: 99,
		TargetAmount:  100,
		Quantity:      99,
	}

	overageAmount := budgetState.CalculateOverage(budget, 10)
	g.Expect(overageAmount).To(gomega.Equal(int64(0)))
}

func Test_MaxOverageAmount(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	g.Expect(MaxOverageAmount([]int64{10, 0, 99})).To(gomega.Equal(int64(99)))
	g.Expect(MaxOverageAmount([]int64{98, 100, 99})).To(gomega.Equal(int64(100)))
	g.Expect(MaxOverageAmount([]int64{0, 0, 0})).To(gomega.Equal(int64(0)))
	g.Expect(MaxOverageAmount([]int64{-98, -100, -99})).To(gomega.Equal(int64(0)))
	g.Expect(MaxOverageAmount([]int64{})).To(gomega.Equal(int64(0)))
}
