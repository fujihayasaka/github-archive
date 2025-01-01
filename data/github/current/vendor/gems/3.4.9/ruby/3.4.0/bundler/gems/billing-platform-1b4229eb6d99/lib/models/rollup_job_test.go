package models

import (
	"reflect"
	"testing"
)

func Test_New_Failed_RollupJob(t *testing.T) {
	processorType := Hourly
	to := UsagePartitionType(ByCustomerSku)
	from := UsagePartitionType(ByCustomer)
	item := Item{}
	aggregationType := NormalUsageAggregation
	keysToIgnore := []string{"ActorId", "OrganizationId"}

	testRollupJob := NewFailedRollupJob(processorType, item, aggregationType, from, to, keysToIgnore)

	if testRollupJob.ProcessorType != processorType {
		t.Errorf("Expected ProcessorType to be %v, got %v", processorType, testRollupJob.ProcessorType)
	}
	if testRollupJob.AggregationType != aggregationType {
		t.Errorf("Expected AggregationType to be %v, got %v", aggregationType, testRollupJob.AggregationType)
	}
	if testRollupJob.To != to {
		t.Errorf("Expected To to be %v, got %v", to, testRollupJob.To)
	}
	if testRollupJob.From != from {
		t.Errorf("Expected From to be %v, got %v", from, testRollupJob.From)
	}
	if !reflect.DeepEqual(testRollupJob.KeysToIgnore, keysToIgnore) {
		t.Errorf("Expected KeysToIgnore to be %v, got %v", keysToIgnore, testRollupJob.KeysToIgnore)
	}
}
