package models

type WorkerType string

const (
	UnknownWorkerType                          WorkerType = ""
	WorkerTypeUsageIngestion                   WorkerType = "usage-ingestion"
	WorkerTypeCustomerDailyRollup              WorkerType = "customer-daily-rollup"
	WorkerTypeCustomerMonthlyRollup            WorkerType = "customer-monthly-rollup"
	WorkerTypeCustomerYearlyRollup             WorkerType = "customer-yearly-rollup"
	WorkerTypeCustomerAzureEmissionDailyRollup WorkerType = "customer-azure-emission-daily-rollup"
	WorkerTypeAzureEmission                    WorkerType = "azure-emission"
	WorkerTypeInvoiceGeneration                WorkerType = "invoice-generation"
	WorkerTypeRequestHandler                   WorkerType = "request-handler"
	WorkerTypeWatermarkHandler                 WorkerType = "watermark-handler"
	WorkerTypeZeroOutQuantities                WorkerType = "zero-out-quantities-handler"
	WorkerTypeHighWatermarkRolloverHandler     WorkerType = "high-watermark-rollover-handler"
	WorkerTypeUsageReport                      WorkerType = "usage-report"
	WorkerTypeUsageReportFanOut                WorkerType = "usage-report-fan-out"
	WorkerTypeEmissionHandler                  WorkerType = "emission-handler"
	WorkerTypeFailedRollups                    WorkerType = "failed-rollups"
	WorkerTypeCustomerZuoraEmissionDailyRollup WorkerType = "customer-zuora-emission-daily-rollup"
	WorkerTypeDiscountStateUpdate              WorkerType = "discount-state-update"
	WorkerTypeZuoraBatchEmissionHandler        WorkerType = "zuora-batch-emission-handler"
	WorkerTypeThrottledWatermark               WorkerType = "throttled-watermark"
	WorkerTypeBulkUsageEmission                WorkerType = "bulk-usage-emission"
	WorkerTypeBudgetState                      WorkerType = "budget-state"
)

// String returns the string value of the WorkerType
func (wt WorkerType) String() string {
	return string(wt)
}
