package api

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/streaming"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blockblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/service"
	"github.com/github/actions-usage-metrics/internal/blob"
	"github.com/github/actions-usage-metrics/internal/export"
	"github.com/github/actions-usage-metrics/internal/repositories"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/google/uuid"
	"github.com/twitchtv/twirp"
)

// StartExport starts an async export job and returns the export ID to check the status.
func (api *UsageApi) StartExport(ctx context.Context, request *proto.StartExportRequest) (*proto.StartExportResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.StartExport")
	defer span.End()

	requestOptions := request.GetRequestOptions()
	err := validateRequest(requestOptions)
	if err != nil {
		return nil, err
	}

	// Validate request options
	if requestOptions.DateRange == nil {
		return nil, twirp.RequiredArgumentError("DateRange")
	} else if len(request.Headers) == 0 {
		return nil, twirp.RequiredArgumentError("Headers")
	}

	// Generate export ID
	exportId := uuid.New().String()
	exportType := request.ExportType
	logger := api.telem.Logger.WithContext(ctx).WithFields(
		kvp.String(telemetry.OTelKeyExportId, exportId),
		kvp.Int64p(telemetry.OTelKeyOwnerId, requestOptions.Scope.OwnerId),
		kvp.Int64p(telemetry.OTelKeyScopeRepoId, requestOptions.Scope.RepositoryId),
		kvp.String(telemetry.OTelKeyExportType, exportType.String()),
	)

	blobName := getBlobName(requestOptions.Scope, exportId)
	statusBlobClient := blob.GetBlockBlobClient(blob.GetContainerClient(export.ExportStatusContainerName), blobName)

	// Make sure the export status is updated to pending before returning
	err = api.updateExportStatus(ctx, logger, statusBlobClient, proto.ExportStatus_EXPORT_STATUS_PENDING)
	if err != nil {
		logger.WithError(err).Error("Failed to set initial export status")
		return nil, twirp.InternalErrorWith(err)
	}

	// start a background job to generate the export
	go func() {
		ctx := context.WithoutCancel(ctx)
		logger := logger.WithContext(ctx)
		start := time.Now()
		statter := api.telem.Stats
		statsTags := stats.Tags{telemetry.ExportTypeKey: exportType.String()}

		err := api.runExport(ctx, logger, request, exportId, statusBlobClient)
		if err != nil {
			logger.WithError(err).Error("Failed to run export")
			failedTags := statsTags.Merge(stats.Tags{telemetry.ExportStatusKey: telemetry.FailedStatus})
			statter.Counter(telemetry.ExportCount_StatsKey, failedTags, 1)
			statter.DistributionMs(telemetry.ExportDuration_StatsKey, failedTags, time.Since(start))
			return
		}

		logger.Info("Export completed", kvp.Duration(telemetry.OTelKeyDuration, time.Since(start)))
		successTags := statsTags.Merge(stats.Tags{telemetry.ExportStatusKey: telemetry.SuccessStatus})
		statter.Counter(telemetry.ExportCount_StatsKey, successTags, 1)
		statter.DistributionMs(telemetry.ExportDuration_StatsKey, successTags, time.Since(start))
	}()

	return &proto.StartExportResponse{
		ExportId: exportId,
	}, nil
}

// GetExportStatus returns the status of an export job and a download URL if the export is complete.
func (api *UsageApi) GetExportStatus(ctx context.Context, request *proto.GetExportStatusRequest) (*proto.GetExportStatusResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetExportStatus")
	defer span.End()

	if len(request.ExportId) == 0 {
		return nil, twirp.RequiredArgumentError("ExportId")
	}

	err := uuid.Validate(request.ExportId)
	if err != nil {
		return nil, err
	}

	err = validateScope(request.Scope)
	if err != nil {
		return nil, err
	}

	exportId := request.ExportId
	statter := api.telem.Stats

	logger := api.telem.Logger.WithContext(ctx).WithFields(
		kvp.String(telemetry.OTelKeyExportId, exportId),
		kvp.Int64p(telemetry.OTelKeyOwnerId, request.Scope.OwnerId),
		kvp.Int64p(telemetry.OTelKeyScopeRepoId, request.Scope.RepositoryId),
	)

	blobName := getBlobName(request.Scope, exportId)
	statusBlobClient := blob.GetBlockBlobClient(blob.GetContainerClient(export.ExportStatusContainerName), blobName)

	start := time.Now()
	statsTags := stats.Tags{telemetry.StatusKey: telemetry.SuccessStatus}
	status, err := api.getExportStatus(ctx, logger, statusBlobClient)
	if err != nil {
		logger.WithError(err).Error("Failed to get export status")
		statsTags = stats.Tags{telemetry.StatusKey: telemetry.FailedStatus}
	}

	statsTags = statsTags.Merge(stats.Tags{telemetry.ExportStatusKey: status.String()})
	statter.Counter(telemetry.ExportGetStatusCount_StatsKey, statsTags, 1)
	statter.DistributionMs(telemetry.ExportGetStatusDuration_StatsKey, statsTags, time.Since(start))

	if err != nil {
		return nil, err
	}

	var downloadUrl string
	if *status == proto.ExportStatus_EXPORT_STATUS_COMPLETE {
		start = time.Now()
		statsTags = stats.Tags{telemetry.StatusKey: telemetry.SuccessStatus}
		downloadUrl, err = api.getExportDownloadUrl(ctx, logger, request.Scope, exportId)
		if err != nil {
			logger.WithError(err).Error("Failed to get download URL")
			statsTags = stats.Tags{telemetry.StatusKey: telemetry.FailedStatus}
		}
		statter.Counter(telemetry.ExportGetDownloadURLCount_StatsKey, statsTags, 1)
		statter.DistributionMs(telemetry.ExportGetDownloadURLDuration_StatsKey, statsTags, time.Since(start))

		if err != nil {
			return nil, err
		}
	}

	return &proto.GetExportStatusResponse{Status: *status, DownloadUrl: downloadUrl}, nil
}

func getBlobName(scope *proto.Scope, exportId string) string {

	blobName := fmt.Sprintf("owner-%d/%s.csv", *scope.OwnerId, exportId)

	if scope.ScopeType == proto.ScopeType_SCOPE_TYPE_REPO {
		blobName = fmt.Sprintf("owner-%d-%d/%s.csv", *scope.OwnerId, *scope.RepositoryId, exportId)
	}

	return blobName
}

// runExport gets usage data, generates a CSV and uploads it to blob storage.
func (api *UsageApi) runExport(ctx context.Context, logger log.Logger, request *proto.StartExportRequest, exportId string, statusBlobClient *blockblob.Client) error {
	ctx, span := telemetry.Trace(ctx, "UsageApi.runExport")
	defer span.End()

	logger.Info("Starting export...")

	blobName := getBlobName(request.RequestOptions.Scope, exportId)

	var err error
	var csvFile *os.File

	// Every X seconds, update the status to indicate that the export is still in progress
	heartbeatTicker := time.NewTicker(export.UpdateStatusEveryDuration)
	stopHeartbeat := make(chan struct{})
	go func() {
		for {
			select {
			case <-heartbeatTicker.C:
				api.updateExportStatus(ctx, logger, statusBlobClient, proto.ExportStatus_EXPORT_STATUS_PENDING)
			case <-stopHeartbeat:
				heartbeatTicker.Stop()
				return
			}
		}
	}()

	// Get response based on export type
	exportType := request.ExportType
	switch exportType {
	case proto.ExportType_EXPORT_TYPE_JOB_USAGE:
		csvFile, err = api.getJobUsageCsvFile(ctx, logger, request, exportId)
	case proto.ExportType_EXPORT_TYPE_REPO_USAGE:
		csvFile, err = api.getRepoUsageCsvFile(ctx, logger, request, exportId)
	case proto.ExportType_EXPORT_TYPE_RUNNER_RUNTIME_USAGE:
		csvFile, err = api.getRunnerRuntimeUsageCsvFile(ctx, logger, request, exportId)
	case proto.ExportType_EXPORT_TYPE_RUNNER_TYPE_USAGE:
		csvFile, err = api.getRunnerTypeUsageCsvFile(ctx, logger, request, exportId)
	case proto.ExportType_EXPORT_TYPE_WORKFLOW_USAGE:
		csvFile, err = api.getWorkflowUsageCsvFile(ctx, logger, request, exportId)
	case proto.ExportType_EXPORT_TYPE_WORKFLOW_PERFORMANCE:
		csvFile, err = api.getWorkflowPerformanceCsvFile(ctx, logger, request, exportId)
	default:
		return fmt.Errorf("unknown export type: %s", exportType.String())
	}
	if err != nil {
		close(stopHeartbeat)
		go api.updateExportStatus(ctx, logger, statusBlobClient, proto.ExportStatus_EXPORT_STATUS_FAILED)
		return fmt.Errorf("failed to get CSV file: %w", err)
	}

	// The OS is likely to clean up temporary files by itself after some time, but it’s good practice to do this explicitly.
	defer os.Remove(csvFile.Name())

	// Upload the CSV to blob storage
	csvBlobClient := blob.GetBlockBlobClient(blob.GetContainerClient(export.ExportContainerName), blobName)
	_, err = csvBlobClient.UploadFile(ctx, csvFile, &azblob.UploadFileOptions{
		// If Progress is non-nil, this function is called periodically as bytes are uploaded.
		Progress: func(bytesTransferred int64) {
			logger.Info("Uploading...", kvp.Int64(telemetry.OTelKeyBytesTransferred, bytesTransferred))
		},
	})
	if err != nil {
		close(stopHeartbeat)
		go api.updateExportStatus(ctx, logger, statusBlobClient, proto.ExportStatus_EXPORT_STATUS_FAILED)
		return fmt.Errorf("failed to upload file: %w", err)
	}

	logger.Info("File uploaded", kvp.String(telemetry.OTelKeyBlobName, blobName))
	close(stopHeartbeat)
	go api.updateExportStatus(ctx, logger, statusBlobClient, proto.ExportStatus_EXPORT_STATUS_COMPLETE)

	logger.Info("Setting blob expiry...")
	_, err = csvBlobClient.SetExpiry(ctx, blockblob.ExpiryTypeRelativeToNow(export.BlobExpiryTimeRelativeToNow), nil)
	if err != nil {
		logger.WithError(err).Error("Failed to set expiry")
	}
	return nil
}

// updateExportStatus updates the export status blob in blob storage.
func (api *UsageApi) updateExportStatus(ctx context.Context, logger log.Logger, statusBlobClient *blockblob.Client, status proto.ExportStatus) error {
	ctx, span := telemetry.Trace(ctx, "UsageApi.updateExportStatus")
	defer span.End()

	logger.Debug("Updating export status...", kvp.String(telemetry.OTelKeyStatus, status.String()))

	start := time.Now()
	statter := api.telem.Stats
	statsTags := stats.Tags{telemetry.ExportStatusKey: status.String()}

	statusMetadata := status.String()
	_, err := statusBlobClient.Upload(ctx, streaming.NopCloser(strings.NewReader("")), &blockblob.UploadOptions{
		Metadata: map[string]*string{
			export.BlobStatusMetadataKey: &statusMetadata,
		},
	})
	if err != nil {
		logger.WithError(err).Error("Failed to update export status")
		err = fmt.Errorf("failed to update export status: %w", err)
		statsTags = statsTags.Merge(stats.Tags{telemetry.StatusKey: telemetry.FailedStatus})
	} else {
		statsTags = statsTags.Merge(stats.Tags{telemetry.StatusKey: telemetry.SuccessStatus})
	}
	statter.Counter(telemetry.ExportUpdateStatusCount_StatsKey, statsTags, 1)
	statter.DistributionMs(telemetry.ExportUpdateStatusDuration_StatsKey, statsTags, time.Since(start))

	if err != nil {
		return err
	}

	return nil
}

// getExportStatus returns the status of the export job.
func (api *UsageApi) getExportStatus(ctx context.Context, logger log.Logger, statusBlobClient *blockblob.Client) (*proto.ExportStatus, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.getExportStatus")
	defer span.End()

	logger = logger.WithContext(ctx)
	logger.Info("Getting export status...")

	blobProperties, err := statusBlobClient.GetProperties(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get blob properties: %w", err)
	}

	statusMetadata := blobProperties.Metadata[export.BlobStatusMetadataKey]
	if statusMetadata == nil {
		return nil, fmt.Errorf("missing status metadata")
	}
	status := proto.ExportStatus(proto.ExportStatus_value[*statusMetadata])

	// If the status is pending and the blob hasn't been updated in the last minute, consider it failed
	if status == proto.ExportStatus_EXPORT_STATUS_PENDING && time.Since(*blobProperties.LastModified) > export.ExportTimeoutAfterDuration {
		status = proto.ExportStatus_EXPORT_STATUS_FAILED
	}

	return &status, nil
}

// getExportDownloadUrl returns the SAS URL to download the blob.
func (api *UsageApi) getExportDownloadUrl(ctx context.Context, logger log.Logger, scope *proto.Scope, exportId string) (string, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.getExportDownloadUrl")
	defer span.End()

	// validate request options
	logger = logger.WithContext(ctx)
	logger.Info("Generating download link...")

	blobName := getBlobName(scope, exportId)

	// Generate SAS token for blob
	sasTokenStartTime := time.Now().Add(export.SasTokenStartTimeRelativeToNow)
	sasTokenEndTime := sasTokenStartTime.Add(export.SasTokenEndTimeRelativeToNow)
	blobPermissions := sas.BlobPermissions{Read: true} // read-only permissions
	blobSasSig := sas.BlobSignatureValues{
		ContainerName: export.ExportContainerName,
		BlobName:      blobName,
		StartTime:     sasTokenStartTime.UTC(),
		ExpiryTime:    sasTokenEndTime.UTC(),
		Permissions:   blobPermissions.String(),
	}
	keyInfo := service.KeyInfo{
		Start:  to.Ptr(sasTokenStartTime.UTC().Format(sas.TimeFormat)),
		Expiry: to.Ptr(sasTokenEndTime.UTC().Format(sas.TimeFormat)),
	}
	serviceClient := blob.BlobClient().ServiceClient()

	// User delegation credentials means that the SAS cannot have more permissions than the user
	userDelegationCredential, err := serviceClient.GetUserDelegationCredential(ctx, keyInfo, nil)
	if err != nil {
		return "", fmt.Errorf("failed to get user delegation credential: %w", err)
	}
	sasQueryParams, err := blobSasSig.SignWithUserDelegation(userDelegationCredential)
	if err != nil {
		return "", fmt.Errorf("failed to sign with user delegation: %w", err)
	}

	// Build URL with SAS to blob
	sasUrl := serviceClient.URL()
	if !strings.HasSuffix(sasUrl, "/") {
		// add a trailing slash to be consistent with the portal
		sasUrl += "/"
	}
	sasUrl += export.ExportContainerName + "/" + blobName
	sasUrl += "?" + sasQueryParams.Encode()

	return sasUrl, nil
}

func (api *UsageApi) getJobUsageCsvFile(ctx context.Context, logger log.Logger, request *proto.StartExportRequest, exportId string) (*os.File, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.getJobUsageCsvFile")
	defer span.End()

	logger.Info("Exporting job usage...")
	response, err := api.GetJobUsage(ctx, &proto.GetJobUsageRequest{
		RequestOptions: request.RequestOptions,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get job usage: %w", err)
	}

	repoIds := utils.Map(response.Items, func(itm *proto.JobUsageItem, _ int) int64 {
		return itm.RepositoryId
	})

	svc := repositories.GetRepositoryService()
	setMappedScope(request.RequestOptions.Scope, api.apiServerCfg.Kusto)
	repoMap, err := svc.GetRepositoryNames(ctx, request.RequestOptions.Scope, repoIds)
	if err != nil {
		return nil, fmt.Errorf("failed to get repo map: %w", err)
	}

	exporter := export.NewExporter(request.Headers, response.Items, export.NewJobUsageExportProvider(repoMap))

	csvFile, err := exporter.CreateCsvFile(exportId)
	if err != nil {
		return nil, fmt.Errorf("failed to create CSV file: %w", err)
	}
	return csvFile, nil
}

func (api *UsageApi) getRepoUsageCsvFile(ctx context.Context, logger log.Logger, request *proto.StartExportRequest, exportId string) (*os.File, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.getRepoUsageCsvFile")
	defer span.End()

	logger.Info("Exporting repo usage...")
	response, err := api.GetRepoUsage(ctx, &proto.GetRepoUsageRequest{
		RequestOptions: request.RequestOptions,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get repo usage: %w", err)
	}

	repoIds := utils.Map(response.Items, func(itm *proto.RepoUsageItem, _ int) int64 {
		return itm.RepositoryId
	})

	svc := repositories.GetRepositoryService()
	setMappedScope(request.RequestOptions.Scope, api.apiServerCfg.Kusto)
	repoMap, err := svc.GetRepositoryNames(ctx, request.RequestOptions.Scope, repoIds)
	if err != nil {
		return nil, fmt.Errorf("failed to get repo map: %w", err)
	}

	exporter := export.NewExporter(request.Headers, response.Items, export.NewRepoUsageExportProvider(repoMap))
	csvFile, err := exporter.CreateCsvFile(exportId)
	if err != nil {
		return nil, fmt.Errorf("failed to create CSV file: %w", err)
	}
	return csvFile, nil
}

func (api *UsageApi) getRunnerRuntimeUsageCsvFile(ctx context.Context, logger log.Logger, request *proto.StartExportRequest, exportId string) (*os.File, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.getRunnerRuntimeUsageCsvFile")
	defer span.End()

	logger.Info("Exporting RunnerRuntime usage...")
	response, err := api.GetRunnerRuntimeUsage(ctx, &proto.GetRunnerRuntimeUsageRequest{
		RequestOptions: request.RequestOptions,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get runtime usage: %w", err)
	}
	exporter := export.NewExporter(request.Headers, response.Items, export.RunnerRuntimeUsageExportProvider)
	csvFile, err := exporter.CreateCsvFile(exportId)
	if err != nil {
		return nil, fmt.Errorf("failed to create CSV file: %w", err)
	}
	return csvFile, nil
}

func (api *UsageApi) getRunnerTypeUsageCsvFile(ctx context.Context, logger log.Logger, request *proto.StartExportRequest, exportId string) (*os.File, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.getRunnerTypeUsageCsvFile")
	defer span.End()

	logger.Info("Exporting RunnerType usage...")
	response, err := api.GetRunnerTypeUsage(ctx, &proto.GetRunnerTypeUsageRequest{
		RequestOptions: request.RequestOptions,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get runnertype usage: %w", err)
	}
	exporter := export.NewExporter(request.Headers, response.Items, export.RunnerTypeUsageExportProvider)
	csvFile, err := exporter.CreateCsvFile(exportId)
	if err != nil {
		return nil, fmt.Errorf("failed to create CSV file: %w", err)
	}
	return csvFile, nil
}

func (api *UsageApi) getWorkflowUsageCsvFile(ctx context.Context, logger log.Logger, request *proto.StartExportRequest, exportId string) (*os.File, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.getWorkflowUsageCsvFile")
	defer span.End()

	logger.Info("Exporting Workflow usage...")
	response, err := api.GetUsageByRepoWorkflowRunner(ctx, &proto.GetUsageByRepoWorkflowRunnerRequest{
		RequestOptions: request.RequestOptions,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get workflow usage: %w", err)
	}

	repoIds := utils.Map(response.Items, func(itm *proto.RepoWorkflowRunnerUsageItem, _ int) int64 {
		return itm.RepositoryId
	})

	svc := repositories.GetRepositoryService()
	setMappedScope(request.RequestOptions.Scope, api.apiServerCfg.Kusto)
	repoMap, err := svc.GetRepositoryNames(ctx, request.RequestOptions.Scope, repoIds)
	if err != nil {
		return nil, fmt.Errorf("failed to get repo map: %w", err)
	}

	exporter := export.NewExporter(request.Headers, response.Items, export.NewWorkflowUsageExportProvider(repoMap))
	csvFile, err := exporter.CreateCsvFile(exportId)
	if err != nil {
		return nil, fmt.Errorf("failed to create CSV file: %w", err)
	}
	return csvFile, nil
}

func (api *UsageApi) getWorkflowPerformanceCsvFile(ctx context.Context, logger log.Logger, request *proto.StartExportRequest, exportId string) (*os.File, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.getWorkflowUsageCsvFile")
	defer span.End()

	logger.Info("Exporting Workflow performance...")
	response, err := api.GetWorkflowPerformance(ctx, &proto.GetWorkflowPerformanceRequest{
		RequestOptions: request.RequestOptions,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get workflow performance: %w", err)
	}

	repoIds := utils.Map(response.Items, func(itm *proto.WorkflowPerformanceItem, _ int) int64 {
		return itm.RepositoryId
	})

	svc := repositories.GetRepositoryService()
	setMappedScope(request.RequestOptions.Scope, api.apiServerCfg.Kusto)
	repoMap, err := svc.GetRepositoryNames(ctx, request.RequestOptions.Scope, repoIds)
	if err != nil {
		return nil, fmt.Errorf("failed to get repo map: %w", err)
	}

	exporter := export.NewExporter(request.Headers, response.Items, export.NewWorkflowPerformanceExportProvider(repoMap))
	csvFile, err := exporter.CreateCsvFile(exportId)
	if err != nil {
		return nil, fmt.Errorf("failed to create CSV file: %w", err)
	}
	return csvFile, nil
}
