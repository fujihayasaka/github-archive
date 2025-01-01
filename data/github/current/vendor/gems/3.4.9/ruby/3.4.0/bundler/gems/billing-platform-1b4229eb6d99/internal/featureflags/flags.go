package featureflags

const (
	// Rollout Zuora daily emissions flow
	ShouldProcessZuoraDailyEmission = "billing_should_process_zuora_daily_emission"

	// Rollout of logging watermark totals
	ShouldLogWatermarkTotals = "billing_platform_should_log_watermark_totals"

	// Rollout of emitting watermark totals
	ShouldEmitWatermarkTotals = "billing_platform_should_emit_watermark_totals"

	// Rollout of sending usage to throttled watermark queue
	SendUsageToThrottledWatermarkQueue = "billing_platform_send_usage_to_throttled_watermark_queue"

	// Rollout of sending all budget updates to a separate queue
	SendAllBudgetUpdatesToQueue = "billing_send_all_budget_updates_to_queue"

	// Rollout updated get usage total endpoint
	UpdateGetUsageTotal = "billing_update_get_usage_total"

	// Rollout of billing idempotent key changes for usage handler rerun
	IdempotentKeyForUsageHandlerRerun = "billing_idempotent_key_for_usage_handler_rerun"

	// Rollout of billing proration for licensed products
	BillingProrationForLicensedProducts = "billing_proration_for_licensed_products"

	// Rollout of high cardinality partition key for watermark events
	UseHighCardinalEventsPartitionKey = "use_billing_high_cardinal_events_partition_key"

	// Rollout of free sku usage fix for CanProceedWithUsage
	FreeSkuCheckEnabled = "billing_free_sku_check_enabled"

	// Rollout cost center query caching
	CostCenterQueryCaching = "billing_cost_center_query_caching"
)
