package models

type FailedRollupJob struct {
	ProcessorType   ActiveType
	AggregationType RollupJobAggregationType
	From            UsagePartitionType
	To              UsagePartitionType
	Item            Item
	KeysToIgnore    []string
}

type RollupJobAggregationType int

const (
	DiscountUsageAggregation RollupJobAggregationType = iota
	NormalUsageAggregation
)

func NewFailedRollupJob(processorType ActiveType, item Item, aggregationType RollupJobAggregationType, from UsagePartitionType, to UsagePartitionType, keysToIgnore []string) *FailedRollupJob {
	return &FailedRollupJob{
		AggregationType: aggregationType,
		ProcessorType:   processorType,
		From:            from,
		To:              to,
		KeysToIgnore:    keysToIgnore,
		Item:            item,
	}
}
