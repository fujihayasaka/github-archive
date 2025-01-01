package models

import (
	"encoding/json"

	"github.com/pkg/errors"
)

type RequestType string

const (
	ProcessDeadLetterQueue           RequestType = "process-dead-letter-queue"
	ScheduleAzureEmission            RequestType = "schedule-azure-emission"
	ScheduleInvoiceGeneration        RequestType = "schedule-invoice-generation"
	ScheduleUsageReportJobs          RequestType = "schedule-usage-report-jobs"
	ScheduleWatermarkJobs            RequestType = "schedule-watermark-jobs"
	ScheduleZeroOutQuantitiesJobs    RequestType = "schedule-zero-out-quantities-jobs"
	ScheduleHighWatermarkRolloverJob RequestType = "schedule-high-watermark-rollover-jobs"
	HighWatermarkUsageRequest        RequestType = "high-watermark-usage-request"
	ScheduleEmission                 RequestType = "schedule-emission"
)

type Request struct {
	Type RequestType
	Data json.RawMessage
}

type ProcessDeadLetterQueueData struct {
	DeadLetterQueueName string
	Num                 int64
}

type ProcessZeroOutQuantitiesData struct {
	CustomerIDs []string
}

func NewProcessDeadLetterQueueRequest(requestData *ProcessDeadLetterQueueData) (*Request, error) {
	data, err := json.Marshal(requestData)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal process dead letter queue data")
	}

	return &Request{
		Type: ProcessDeadLetterQueue,
		Data: data,
	}, nil
}

func NewScheduleUsageReportJobsRequest() (*Request, error) {
	return &Request{
		Type: ScheduleUsageReportJobs,
	}, nil
}

func NewScheduleAzureEmissionRequest(target *AzureUsageDate) (*Request, error) {
	data, err := json.Marshal(target)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal azure emission target data")
	}

	return &Request{
		Type: ScheduleAzureEmission,
		Data: data,
	}, nil
}

func NewScheduleInvoiceGenerationRequest(ipd *InvoicePartitionDetail) (*Request, error) {
	data, err := json.Marshal(ipd)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal invoice partition detail data")
	}

	return &Request{
		Type: ScheduleInvoiceGeneration,
		Data: data,
	}, nil
}

func NewScheduleWatermarkJobsRequest(jobRun *WatermarkJobRun) (*Request, error) {
	data, err := json.Marshal(jobRun)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal watermark job run data")
	}

	return &Request{
		Type: ScheduleWatermarkJobs,
		Data: data,
	}, nil
}

func NewScheduleZeroOutQuantitiesJobsRequest(jobRun *ZeroOutQuantitiesJobRun) (*Request, error) {
	data, err := json.Marshal(jobRun)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal zero out quantities job run data")
	}

	return &Request{
		Type: ScheduleZeroOutQuantitiesJobs,
		Data: data,
	}, nil
}

func NewScheduleHighWatermarkRolloverJobRequest(jobRun *HighWatermarkRolloverJobRun) (*Request, error) {
	data, err := json.Marshal(jobRun)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal high watermark rollover job run data")
	}

	return &Request{
		Type: ScheduleHighWatermarkRolloverJob,
		Data: data,
	}, nil
}

func NewScheduleEmissionRequest(target *UsageDate) (*Request, error) {
	data, err := json.Marshal(target)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal emission target data")
	}

	return &Request{
		Type: ScheduleEmission,
		Data: data,
	}, nil
}
