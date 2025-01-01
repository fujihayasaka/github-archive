package kusto

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/Azure/azure-kusto-go/azkustodata"
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/github/billing-platform/lib/azure/sas"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

const (
	// The database name to execute queries for.
	// Queries that specify the database via database('DB_NAME') can bypass this
	HydroDatabaseName = "hydro"
)

type AzureKustoService struct {
	client     *azkustodata.Client
	sasService sas.SasService
	statter    stats.Client
	logger     log.Logger
}

type KustoService interface {
	SubmitExportRequest(ctx context.Context, blobStorageContainerName string, usageReport *models.UsageReportExport, isProxima bool) (string, error)
	GetExportStatus(ctx context.Context, usageReportExport *models.UsageReportExport) (models.KustoOperationStatus, error)
	GetExportBlobs(ctx context.Context, usageReportExport *models.UsageReportExport) ([]string, error)
	GetTopReposByGrossAmount(ctx context.Context, input *models.UsageRequest) ([]int64, error)
	GetTopOrgsByGrossAmount(ctx context.Context, input *models.UsageRequest) ([]int64, error)
	GetDistinctOrgOrRepoTotalCount(ctx context.Context, input *proto.GetPaginatedUsageRequest) (int64, error)
}

func New(cfg *config.Config, statter stats.Client, logger log.Logger) (KustoService, error) {
	cred, err := azidentity.NewClientSecretCredential(cfg.KustoSpnTenantId, cfg.KustoSpnClientId, cfg.KustoSpnClientSecret, nil)
	if err != nil {
		return nil, errors.Wrap(err, "error creating kusto credential")
	}

	kustoConnectionStringBuilder := azkustodata.NewConnectionStringBuilder(cfg.KustoEndpoint).WithTokenCredential(cred)
	client, err := azkustodata.New(kustoConnectionStringBuilder)
	if err != nil {
		return nil, errors.Wrap(err, "error creating kusto client")
	}

	sasService, err := sas.New(cfg, statter, cfg.KustoBlobExportStorageAccountEndpoint)
	if err != nil {
		return nil, errors.Wrap(err, "error creating SAS service")
	}

	return AzureKustoService{
		client:     client,
		sasService: sasService,
		statter:    statter,
		logger:     logger,
	}, nil
}

func (k AzureKustoService) SubmitExportRequest(ctx context.Context, blobStorageContainerName string, usageReport *models.UsageReportExport, isProxima bool) (string, error) {
	startTime := time.Now()

	// SAS URLs for export blobs require read/write/list permissions
	sasUrl, err := k.sasService.ReadWriteListSas(blobStorageContainerName)
	if err != nil {
		return "", errors.Wrap(err, "error getting SAS URL")
	}

	var query *kql.Builder
	if usageReport.LegacyReport {
		query = k.BuildSubmitLegacyExportRequestQuery(ctx, usageReport, sasUrl, isProxima)
	} else {
		query = k.BuildSubmitExportRequestQuery(ctx, usageReport, sasUrl, isProxima)
	}

	// We use .Mgmt here instead of .Query since control commands (starting with ".") are not allowed in .Query
	results, err := k.client.Mgmt(
		ctx,
		// database to run export operation on, note that the query can still
		// pull from other DBs by specifying the DB in the query via database('db_name').table_name
		HydroDatabaseName,
		query,
		azkustodata.QueryParameters(kql.NewParameters()),
		azkustodata.RequestDescription("billing.export_usage_report"),
	)
	if err != nil {
		return "", errors.Wrap(err, "failed to query")
	}

	var operationUUID string
	for _, table := range results.Tables() {
		if table.IsPrimaryResult() {
			for _, row := range table.Rows() {
				operationUUID = strings.TrimSuffix(row.String(), "\n")
			}
		}
	}

	if operationUUID == "" {
		return "", errors.New("failed to get operation UUID")
	}

	k.statter.Counter("kusto.export.count", stats.Tags{"legacyReport": strconv.FormatBool(usageReport.LegacyReport)}, 1)
	k.statter.DistributionMs("kusto.export.request", nil, time.Since(startTime))

	return operationUUID, nil
}

// Get an export operation status from Kusto
func (k AzureKustoService) GetExportStatus(ctx context.Context, usageReportExport *models.UsageReportExport) (models.KustoOperationStatus, error) {
	query := kql.New("").
		AddLiteral(".show operations").
		AddLiteral("	| where OperationId == ").AddString(usageReportExport.ExportOperationUUID).
		AddLiteral("	| order by LastUpdatedOn desc").
		AddLiteral("	| project State").
		AddLiteral("	| take 1")

	// We use .Mgmt here instead of .Query since control commands (starting with ".") are not allowed in .Query
	results, err := k.client.Mgmt(
		ctx,
		// use the database name the export operations are running on
		HydroDatabaseName,
		query,
		azkustodata.QueryParameters(kql.NewParameters()),
		azkustodata.RequestDescription("billing.export_usage_report"),
	)
	if err != nil {
		return "", errors.Wrap(err, "failed to query export status")
	}

	var status string
	// We have a take 1 in the query so it should only ever be one row (or none).
	// The interface to interact with results is a bit obtuse though and AFAIK
	// requires us to iterate over Rows() even if we only expect one.
	for _, table := range results.Tables() {
		if table.IsPrimaryResult() {
			for _, row := range table.Rows() {
				status = strings.TrimSuffix(row.String(), "\n")
			}
		}
	}

	k.statter.Counter("kusto.export.status", stats.Tags{"status": status}, int64(1))

	return models.KustoOperationStatus(status), nil
}

func (k AzureKustoService) GetExportBlobs(ctx context.Context, usageReportExport *models.UsageReportExport) ([]string, error) {
	query := kql.New("").
		AddLiteral(".show operation ").AddString(usageReportExport.ExportOperationUUID).AddLiteral(" details").
		AddLiteral("	| project Path, NumRecords, SizeInBytes")

	// We use .Mgmt here instead of .Query since control commands (starting with ".") are not allowed in .Query
	results, err := k.client.Mgmt(
		ctx,
		// use the database name the export operations are running on
		HydroDatabaseName,
		query,
		azkustodata.QueryParameters(kql.NewParameters()),
		azkustodata.RequestDescription("billing.export_usage_report"),
	)
	if err != nil {
		return []string{}, errors.Wrap(err, "failed to query report status")
	}

	var blobURLs []string
	var totalSizeInBytes int64
	var totalNumberOfRecords int64
	for _, table := range results.Tables() {
		if table.IsPrimaryResult() {
			for _, row := range table.Rows() {
				// each row contains the following columns that we need to parse out of the comma delimited string:
				// Path, NumRecords, SizeInBytes
				fields := strings.Split(row.String(), ",")
				if len(fields) != 3 {
					k.logger.Error(
						"failed to parse blob export operation details",
						kvp.String("exportOperationUUID", usageReportExport.ExportOperationUUID),
						kvp.String("customerId", usageReportExport.CustomerID),
					)
					continue
				}

				blobURL := strings.TrimSuffix(fields[0], "\n")
				numRecords := strings.TrimSuffix(fields[1], "\n")
				sizeInBytes := strings.TrimSuffix(fields[2], "\n")

				// convert numRecords and sizeInBytes to int64
				numRecordsInt, err := strconv.ParseInt(numRecords, 10, 64)
				if err == nil {
					totalNumberOfRecords += numRecordsInt
				}

				sizeInBytesInt, err := strconv.ParseInt(sizeInBytes, 10, 64)
				if err == nil {
					totalSizeInBytes += sizeInBytesInt
				}

				blobURLs = append(blobURLs, blobURL)
			}
		}
	}

	k.statter.Counter("kusto.export.numRecords", nil, totalNumberOfRecords)
	k.statter.Counter("kusto.export.size", nil, totalSizeInBytes)

	return blobURLs, nil
}

func (k AzureKustoService) BuildSubmitLegacyExportRequestQuery(ctx context.Context, usageReportExport *models.UsageReportExport, sasUrl string, isProxima bool) *kql.Builder {
	query := kql.New("")

	// build the .export command
	query.AddLiteral(".export async to csv (")
	query.AddLiteral("h@").AddString(sasUrl)
	// Maximum size limit for a blob from .export is 4GB but the default is 100MB. We set it to 2GB to be safe as this is the maximum allowed by Excel.
	query.AddLiteral(") with ( sizeLimit=2000000000, namePrefix='legacyUsageReport', includeHeaders='all', encoding='UTF8BOM') <| ")

	// build query here
	query.AddLiteral("let startDate = startofday(").AddDateTime(usageReportExport.StartDate).AddLiteral(");")
	query.AddLiteral("let endDate = endofday(").AddDateTime(usageReportExport.EndDate).AddLiteral(");")
	query.AddLiteral("let customerId = ").AddString(usageReportExport.CustomerID).AddLiteral(";")
	query.AddLiteral("database('service_billing').meuse_usage_report_items")
	query.AddLiteral("| where todatetime(day) between(startDate .. endDate) and customer_id == customerId")
	// START DATA FORMATTING - This is to align the data with what used to be generated in Meuse
	// Variables
	query.AddLiteral("| extend isActions = product_name == 'actions'")
	query.AddLiteral("| extend isPackages = product_name == 'packages'")
	query.AddLiteral("| extend isStorage = product_name == 'shared_storage'")
	query.AddLiteral("| extend isCodespaces = product_name == 'codespaces'")
	query.AddLiteral("| extend isCopilot = product_name == 'copilot'")
	// Formating
	query.AddLiteral("| extend rate_plan_unit_price = iff(isStorage, (rate_plan_unit_price * 24 * 1024), rate_plan_unit_price)")
	query.AddLiteral("| extend d_parts = split(workflow_file_path, '/')")
	query.AddLiteral("| extend dynamic_workflow_path = iff((tostring(d_parts[2]) contains tostring(d_parts[1])), d_parts[2], strcat(d_parts[1], ' - ', d_parts[2]))")
	query.AddLiteral("| extend workflow_file_path = case(")
	query.AddLiteral("		isCodespaces and product_sku_name == 'prebuild_storage', 'Create Codespaces Prebuilds',")
	query.AddLiteral("		workflow_file_path startswith('dynamic/'), dynamic_workflow_path,")
	query.AddLiteral("		workflow_file_path)")
	query.AddLiteral("| extend repository_name = case(")
	query.AddLiteral("		isStorage and isempty(repo_id), 'Organization Packages',")
	query.AddLiteral("		isPackages and isempty(repo_id), 'Organization Packages - Data Transfer Out',")
	query.AddLiteral("		isnotempty(repo_id) and isempty(repository_name), 'deleted repository',")
	query.AddLiteral("		repository_name)")
	query.AddLiteral("| extend quantity = case(")
	query.AddLiteral("		isPackages, quantity/1073741824,")   // convert to gigabyte for packages
	query.AddLiteral("		isStorage, quantity/24/1073741824,") // convert to gigabyte-day for storage
	query.AddLiteral("		quantity)")
	query.AddLiteral("| extend unit_of_measure_name = case(")
	query.AddLiteral("		isActions, 'minute',")
	query.AddLiteral("		isPackages, 'gb',")
	query.AddLiteral("		isStorage, 'gb-day',")
	query.AddLiteral("		isCodespaces and product_sku_name in('storage', 'prebuild_storage'), 'gb-month',")
	query.AddLiteral("		isCodespaces and product_sku_name !in('storage', 'prebuild_storage'), 'hour',")
	query.AddLiteral("		isCopilot, 'user-month',")
	query.AddLiteral("		unit_of_measure_name)")
	query.AddLiteral("| extend product_sku_name = case(")
	query.AddLiteral("		isActions, strcat('Compute - ', toupper(replace_string(replace_string(replace_string(product_sku_name, 'linux', 'ubuntu'), 'macos_l', 'macos_large'), 'macos_xl', 'macos_xlarge'))),")
	query.AddLiteral("		isPackages, 'Data Transfer',")
	query.AddLiteral("		isStorage, 'Shared Storage',")
	query.AddLiteral("		isCodespaces and product_sku_name == 'storage', 'Storage',")
	query.AddLiteral("		isCodespaces and product_sku_name == 'prebuild_storage', 'Prebuild storage',")
	query.AddLiteral("		isCodespaces and product_sku_name startswith 'compute_d', strcat(replace_string(product_sku_name, 'compute_d', 'Compute - '), ' core'),")
	query.AddLiteral("		isCopilot and product_sku_name == 'copilot_enterprise', 'Copilot Enterprise',")
	query.AddLiteral("		isCopilot and product_sku_name in('copilot_standalone', 'copilot_for_business'), 'Copilot Business',")
	query.AddLiteral("		isCopilot, 'Copilot',")
	query.AddLiteral("		product_sku_name)")
	query.AddLiteral("| extend product_name = case(")
	query.AddLiteral("		isActions, 'Actions',")
	query.AddLiteral("		isPackages, 'Packages',")
	query.AddLiteral("		isStorage, 'Shared Storage',")
	query.AddLiteral("		isCodespaces, 'Codespaces - Linux',")
	query.AddLiteral("		isCopilot, 'Copilot',")
	query.AddLiteral("		product_name)")
	query.AddLiteral("| extend username = iff(isActions and isempty(username), '[bot]', username)")
	// END DATA FORMATTING"
	query.AddLiteral("| project ")
	query.AddLiteral("		Date=day, Product=product_name, SKU=product_sku_name, Quantity=round(quantity, 4), ['Unit Type']=unit_of_measure_name, ")
	query.AddLiteral("		['Price Per Unit ($)']=round(rate_plan_unit_price*rate_plan_multiplier, 3), Multiplier=rate_plan_multiplier, Owner=organization, ")
	query.AddLiteral("		['Repository Slug']=repository_name, Username=username, ['Actions Workflow']=workflow_file_path, Notes=''")
	query.AddLiteral("| order by Date asc, Product asc, SKU desc, Quantity desc")

	return query
}

func (k AzureKustoService) BuildSubmitExportRequestQuery(ctx context.Context, usageReportExport *models.UsageReportExport, sasUrl string, isProxima bool) *kql.Builder {
	/*
		The kusto SDK is a bit obtuse and requires constant strings or the use of their builder to ensure the query is safe from injection vulnerabilities. Further friction
		comes from the fact that we can not supply query params to the .export command, so we must build the entire query string before submitting it to the engine.
		This query should compile to something like:

		.export
		async
		to csv (
			h@[STORAGE_CONNECTION_STRING]
		)
		with (
			sizeLimit=2000000000,
			namePrefix="usageReport",
			includeHeaders="all",
			encoding="UTF8BOM"
		)
		<|
		database('hydro').billingplatform_v1_usage_line_item
			| where todatetime(usage_at) between([startDate] .. [endDate])
			| where customer_id == [customerID]
			| where org_id == (dynamic([<organizationIDs>]))
			| extend check_run_id=tolong(replace_string(source_uri, 'gid://git-hub/CheckRun/', ''))
		| join kind=leftouter (database('hydro').github_actions_v0_job_execution  | where todatetime(end_time) between ([startDate] .. [endDate]) | project workflow_name, check_run_id) on check_run_id
		| join kind=leftouter (database('snapshots').github_mysql1_repositories_current | project id=tolong(id), repository_name=name) on $left.repo_id==$right.id
		| join kind=leftouter (database("snapshots").github_mysql1_users_current | where type=='User' | project id=tolong(id), username=login) on $left.actor_id==$right.id
		| join kind=leftouter (database("snapshots").github_mysql1_users_current | where type=='Organization' | project id=tolong(id), organization=login) on $left.org_id==$right.id
		| project usage_at, product, sku, quantity, unit_type, applied_cost_per_quantity, gross_amount, discount_amount, net_amount, username, organization, repository_name, workflow_name, cost_center.name
	*/
	query := kql.New("")

	// build the .export command
	query.AddLiteral(".export async to csv (")
	query.AddLiteral("h@").AddString(sasUrl)
	// Maximum size limit for a blob from .export is 4GB but the default is 100MB. We set it to 2GB to be safe as this is the maximum allowed by Excel.
	query.AddLiteral(") with ( sizeLimit=2000000000, namePrefix='usageReport', includeHeaders='all', encoding='UTF8BOM') <| ")

	// build the billingplatform_v1_usage_line_item query for the usage report export request
	query.AddLiteral("database('hydro').billingplatform_v1_usage_line_item")
	query.AddLiteral("	| where todatetime(usage_at) between(").AddDateTime(usageReportExport.StartDate).AddLiteral(" .. ").AddDateTime(usageReportExport.EndDate).AddLiteral(")")
	query.AddLiteral("	| where customer_id == ").AddString(usageReportExport.CustomerID)

	if len(usageReportExport.OrganizationIDs) > 0 {
		query.AddLiteral("	| where org_id in (").AddDynamic(usageReportExport.OrganizationIDs).AddLiteral(")")
	}

	// extend a check_run_id column from the source URI to be able to join with the github_actions_v0_job_execution table
	query.AddLiteral("	| extend check_run_id=tolong(replace_string(source_uri, 'gid://git-hub/CheckRun/', ''))")

	// limit the join to the export date range when getting workflow name to reduce the amount of data we need to join on which speeds up the query
	// end_time and usage_at are the same so we can use the same date range to filter both tables
	query.AddLiteral("| join kind=leftouter (database('hydro').github_actions_v0_job_execution | where todatetime(end_time) between(").AddDateTime(usageReportExport.StartDate).AddLiteral(" .. ").AddDateTime(usageReportExport.EndDate).AddLiteral(") | project workflow_name, workflow_file_path, check_run_id) on check_run_id")

	if isProxima {
		query.AddLiteral("| join kind=leftouter (database('local_warehouse').repositories_daily | project id, repository_name=name) on $left.repo_id==$right.id")
		query.AddLiteral("| join kind=leftouter (database('local_warehouse').users_daily | where type=='User' | project id, username=login) on $left.actor_id==$right.id")
		query.AddLiteral("| join kind=leftouter (database('local_warehouse').users_daily | where type=='Organization' | project id, organization=login) on $left.org_id==$right.id")
	} else {
		query.AddLiteral("| join kind=leftouter (database('snapshots').github_mysql1_repositories_current | project id=tolong(id), repository_name=name) on $left.repo_id==$right.id")
		query.AddLiteral("| join kind=leftouter (database('snapshots').github_mysql1_users_current | where type=='User' | project id=tolong(id), username=login) on $left.actor_id==$right.id")
		query.AddLiteral("| join kind=leftouter (database('snapshots').github_mysql1_users_current | where type=='Organization' | project id=tolong(id), organization=login) on $left.org_id==$right.id")
	}

	// join with other tables to get the necessary data for the export and project the final columns
	query.AddLiteral("| project usage_at, product, sku, quantity, unit_type, applied_cost_per_quantity, gross_amount, discount_amount, net_amount, username, organization, repository_name, workflow_name, workflow_path=workflow_file_path, cost_center.name")

	// sort the results by usage_at to ensure the data is ordered correctly
	query.AddLiteral("| order by todatetime(usage_at) asc")

	return query
}

type OrgRepoQueryType int

const (
	ByOrgQueryType OrgRepoQueryType = iota
	ByRepoQueryType
)

func (k AzureKustoService) GetTopReposByGrossAmount(ctx context.Context, input *models.UsageRequest) ([]int64, error) {
	startTime := time.Now()

	query, err := k.BuildTopOrgsReposByGrossAmountQuery(input, ByRepoQueryType)
	if err != nil {
		return nil, errors.Wrap(err, "failed to build top repos query")
	}

	results, err := k.client.Query(
		ctx,
		HydroDatabaseName,
		query,
		azkustodata.QueryParameters(kql.NewParameters()),
		azkustodata.RequestDescription("billing.top_repos_by_gross_amount"),
	)
	if err != nil {
		return nil, errors.Wrap(err, "failed to query top repos")
	}

	var repoIDs []int64
	for _, table := range results.Tables() {
		if table.IsPrimaryResult() {
			for _, row := range table.Rows() {
				stringRepoId := strings.TrimSuffix(row.String(), "\n")

				repoId, err := strconv.ParseInt(stringRepoId, 10, 64)
				if err == nil {
					repoIDs = append(repoIDs, repoId)
				}
			}
		}
	}

	k.statter.DistributionMs("kusto.query.topRepos", nil, time.Since(startTime))

	return repoIDs, nil
}

func (k AzureKustoService) GetTopOrgsByGrossAmount(ctx context.Context, input *models.UsageRequest) ([]int64, error) {
	startTime := time.Now()

	query, err := k.BuildTopOrgsReposByGrossAmountQuery(input, ByOrgQueryType)
	if err != nil {
		return nil, errors.Wrap(err, "failed to build top orgs query")
	}

	results, err := k.client.Query(
		ctx,
		HydroDatabaseName,
		query,
		azkustodata.QueryParameters(kql.NewParameters()),
		azkustodata.RequestDescription("billing.top_orgs_by_gross_amount"),
	)
	if err != nil {
		return nil, errors.Wrap(err, "failed to query top orgs")
	}

	var orgIDs []int64
	for _, table := range results.Tables() {
		if table.IsPrimaryResult() {
			for _, row := range table.Rows() {
				stringOrgId := strings.TrimSuffix(row.String(), "\n")

				orgId, err := strconv.ParseInt(stringOrgId, 10, 64)
				if err == nil {
					orgIDs = append(orgIDs, orgId)
				}
			}
		}
	}

	k.statter.DistributionMs("kusto.query.topOrgs", nil, time.Since(startTime))

	return orgIDs, nil
}

func (k AzureKustoService) BuildTopOrgsReposByGrossAmountQuery(input *models.UsageRequest, queryType OrgRepoQueryType) (*kql.Builder, error) {
	// convert customerID to a string to match the type of customer_id in the billingplatform_v1_usage_line_item table
	customerIdString := fmt.Sprintf("%d", input.CustomerId)

	query := kql.New("").
		AddLiteral("database('hydro').billingplatform_v1_usage_line_item")

	switch input.CostCenterId {
	// some endpoints in dotcom send 'All' as the cost center ID to get all usage for a customer (including cost center usage)
	case "All":
		query.AddLiteral("	| where customer_id == ").AddString(customerIdString)
	// some endpoints in dotcom send an empty string as the cost center ID to get all usage for a customer (including cost center usage)
	case "":
		query.AddLiteral("	| where customer_id == ").AddString(customerIdString)
	// "none" represents usage not associated with a cost center
	case "none":
		query.AddLiteral("	| where customer_id == ").AddString(customerIdString).AddLiteral(" and cost_center == ''")
	// all other cases are searches for a specific cost center
	default:
		query.AddLiteral("	| where customer_id == ").AddString(customerIdString).AddLiteral(" and cost_center.uuid == ").AddString(input.CostCenterId)
	}

	// filter out any usage records that are not associated with a repo or organization
	if queryType == ByOrgQueryType {
		query.AddLiteral("	| where org_id != 0")
	} else {
		query.AddLiteral("	| where repo_id != 0")
	}

	// filter usage for organization admins requesting usage for their orgs
	if len(input.FilteredOrgs) > 0 {
		query.AddLiteral("	| where org_id in (").AddDynamic(input.FilteredOrgs).AddLiteral(")")
	}

	inputTime := models.NewUsageTime().WithYear(input.Year).WithMonthInt(input.Month).WithDay(int(input.Day)).WithHour(int(input.Hour)).Time

	switch input.BillingPeriod {
	case proto.BillingPeriod_Hourly:
		// KQL does not have a startofhour or endofhour function so we instead just provide an hour offsite of the input usage time
		query.AddLiteral("	| where todatetime(usage_at) between(").AddDateTime(inputTime.Add(-1 * time.Hour)).AddLiteral(" .. ").AddDateTime(inputTime).AddLiteral(")")
	case proto.BillingPeriod_Daily:
		query.AddLiteral("	| where todatetime(usage_at) between(startofday(").AddDateTime(inputTime).AddLiteral(") .. endofday(").AddDateTime(inputTime).AddLiteral("))")
	case proto.BillingPeriod_Monthly:
		query.AddLiteral("	| where todatetime(usage_at) between(startofmonth(").AddDateTime(inputTime).AddLiteral(") .. endofmonth(").AddDateTime(inputTime).AddLiteral("))")
	case proto.BillingPeriod_Yearly:
		query.AddLiteral("	| where todatetime(usage_at) between(startofyear(").AddDateTime(inputTime).AddLiteral(") .. endofyear(").AddDateTime(inputTime).AddLiteral("))")
	default:
		return nil, errors.New("invalid billing period")
	}

	if queryType == ByOrgQueryType {
		query.AddLiteral("	| summarize sum_gross_amount=sum(gross_amount) by org_id").
			AddLiteral("	| order by sum_gross_amount desc").
			AddLiteral("	| take ").AddInt(input.Limit).
			AddLiteral("	| project org_id")
	} else {
		query.AddLiteral("	| summarize sum_gross_amount=sum(gross_amount) by repo_id").
			AddLiteral("	| order by sum_gross_amount desc").
			AddLiteral("	| take ").AddInt(input.Limit).
			AddLiteral("	| project repo_id")
	}
	k.logger.Info("Built query for kusto ", kvp.String("query", query.String()))
	return query, nil
}

func (k AzureKustoService) GetDistinctOrgOrRepoTotalCount(ctx context.Context, input *proto.GetPaginatedUsageRequest) (int64, error) {
	startTime := time.Now()

	query, err := k.BuildDistinctOrgOrRepoTotalCountQuery(input)
	if err != nil {
		return 0, errors.Wrap(err, "failed to build distinct org or repo total count query")
	}

	results, err := k.client.Query(
		ctx,
		HydroDatabaseName,
		query,
		azkustodata.QueryParameters(kql.NewParameters()),
		azkustodata.RequestDescription("billing.distinct_org_or_repo_total_count"),
	)
	if err != nil {
		return 0, errors.Wrap(err, "failed to query distinct org or repo total count")
	}

	for _, table := range results.Tables() {
		if table.IsPrimaryResult() {
			for _, row := range table.Rows() {
				stringTotalCount := strings.TrimSuffix(row.String(), "\n")

				totalCount, err := strconv.ParseInt(stringTotalCount, 10, 64)
				if err == nil {
					if input.GroupBy == proto.UsageGroupBy_GroupByOrganization {
						k.statter.DistributionMs("kusto.query.numDistinctOrgs", nil, time.Since(startTime))
					} else {
						k.statter.DistributionMs("kusto.query.numDistinctRepos", nil, time.Since(startTime))
					}

					return totalCount, nil
				}
			}
		}
	}

	return 0, nil
}

func (k AzureKustoService) BuildDistinctOrgOrRepoTotalCountQuery(input *proto.GetPaginatedUsageRequest) (*kql.Builder, error) {
	query := kql.New("").
		AddLiteral("database('hydro').billingplatform_v1_usage_line_item")

	switch input.CostCenterId {
	case "All":
		query.AddLiteral("	| where customer_id == ").AddString(input.UsageEntityId)
		// TODO remove this case once aggregate usage epic ships : https://github.com/github/gitcoin/issues/16315 . After that we will aways want all usage to include costcenters by default
	case "":
		query.AddLiteral("	| where customer_id == ").AddString(input.UsageEntityId).AddLiteral(" and cost_center == ''")
	default:
		// TODO remove this case once aggregate usage epic ships : https://github.com/github/gitcoin/issues/16315 . After that we will aways want all usage include costcenters by default
		query.AddLiteral("	| where customer_id == ").AddString(input.UsageEntityId).AddLiteral(" and cost_center.uuid == ").AddString(input.CostCenterId)
	}

	// filter out any usage records that are not associated with a repo or organization
	if input.GroupBy == proto.UsageGroupBy_GroupByOrganization {
		query.AddLiteral("	| where org_id != 0")
	} else {
		query.AddLiteral("	| where repo_id != 0")
	}

	// filter out any usage records for SKUs that are not enabled for emissions and thus are not included in rollups which will have a applied_cost_per_quantity of 0
	query.AddLiteral(" and applied_cost_per_quantity != 0")

	// filter usage for organization admins requesting usage for their orgs
	if len(input.OrganizationIds) > 0 {
		query.AddLiteral("	| where org_id in (").AddDynamic(input.OrganizationIds).AddLiteral(")")
	}

	inputTime := models.NewUsageTime().WithYear(input.Year).WithMonthInt(input.Month).WithDay(int(input.Day)).WithHour(int(input.Hour)).Time

	switch input.BillingPeriod {
	case proto.BillingPeriod_Hourly:
		// KQL does not have a startofhour or endofhour function so we instead just provide an hour offsite of the input usage time
		query.AddLiteral("	| where todatetime(usage_at) between(").AddDateTime(inputTime.Add(-1 * time.Hour)).AddLiteral(" .. ").AddDateTime(inputTime).AddLiteral(")")
	case proto.BillingPeriod_Daily:
		query.AddLiteral("	| where todatetime(usage_at) between(startofday(").AddDateTime(inputTime).AddLiteral(") .. endofday(").AddDateTime(inputTime).AddLiteral("))")
	case proto.BillingPeriod_Monthly:
		query.AddLiteral("	| where todatetime(usage_at) between(startofmonth(").AddDateTime(inputTime).AddLiteral(") .. endofmonth(").AddDateTime(inputTime).AddLiteral("))")
	case proto.BillingPeriod_Yearly:
		query.AddLiteral("	| where todatetime(usage_at) between(startofyear(").AddDateTime(inputTime).AddLiteral(") .. endofyear(").AddDateTime(inputTime).AddLiteral("))")
	default:
		return nil, errors.New("invalid billing period")
	}

	if input.GroupBy == proto.UsageGroupBy_GroupByOrganization {
		query.AddLiteral("	| summarize count_distinct(org_id)")
	} else {
		query.AddLiteral("	| summarize count_distinct(repo_id)")
	}

	return query, nil
}
