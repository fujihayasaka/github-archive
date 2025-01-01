package query

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/querybuilder"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type Search struct {
	Search *string
	Column string
}

type QueryOptions struct {
	Scope       *proto.Scope
	StartDay    *time.Time
	EndDay      *time.Time
	Filters     *[]querybuilder.KustoModelFilter
	OrderBy     *[]querybuilder.OrderBy
	OffsetLimit *querybuilder.OffsetLimit
	Search      *Search
	Version     *versioning.Version
}

// Used to limit the fields that can be queried without a tenant.
// Never add fields that contain customer information here.
type AllowedNoTenantField string

const (
	KafkaTimestamp AllowedNoTenantField = "kafka_timestamp"
)

// These are the only tables that can be queried without a tenant.
type AllowedTable string

const (
	RestrictedView AllowedTable = "RestrictedView"
	CommandResults AllowedTable = "$command_results"
)

type KustoQueryBuilder struct {
	QueryProvider
	params *kql.Parameters

	restrictBuilder          *kql.Builder
	managementCommandBuilder *kql.Builder
	baseQueryBuilder         *kql.Builder
	aggregationBuilder       *kql.Builder
	filtersBuilder           *kql.Builder
	searchBuilder            *kql.Builder
	orderByBuilder           *kql.Builder
	pagingBuilder            *kql.Builder
	summarizeBuilder         *kql.Builder

	countOnly bool
}

func NewKustoQueryBuilder(
	tableOrView string,
	aggregationQuery *kql.Builder,
	queryOptions QueryOptions,
	countOnly bool) *KustoQueryBuilder {
	var restrictBuilder *kql.Builder
	if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_ORG {
		restrictBuilder = kql.New(`let RestrictedView = view () { `).AddUnsafe(tableOrView).AddLiteral(` | where repositoryOwnerId == repositoryOwnerIdParam }; restrict access to (RestrictedView);`).AddLiteral("\n")
	} else if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_REPO {
		restrictBuilder = kql.New(`let RestrictedView = view () { `).AddUnsafe(tableOrView).AddLiteral(` | where repositoryOwnerId == repositoryOwnerIdParam and repositoryId == repositoryIdParam }; restrict access to (RestrictedView);`).AddLiteral("\n")
	} else if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_ENTERPRISE {
		restrictBuilder = kql.New(`let RestrictedView = view () { `).AddUnsafe(tableOrView).AddLiteral(` | where repositoryOwnerId in (enterpriseOrgsParam) }; restrict access to (RestrictedView);`).AddLiteral("\n")
	} else {
		return nil
	}

	baseQueryBuilder := kql.New("").AddTable("RestrictedView").AddLiteral("\n")

	params := kql.NewParameters()
	if queryOptions.StartDay != nil && queryOptions.EndDay != nil {
		baseQueryBuilder = baseQueryBuilder.AddLiteral("| where timestamp between (startofday(startDayParam) .. endofday(endDayParam))").AddLiteral("\n")
		params = params.AddDateTime("startDayParam", *queryOptions.StartDay)
		params = params.AddDateTime("endDayParam", *queryOptions.EndDay)
	}

	// ensure there is always a version to check against
	version := versioning.ActiveProjectionVersion_Api

	if queryOptions.Version != nil {
		version = *queryOptions.Version
	}

	if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_ORG {
		baseQueryBuilder = baseQueryBuilder.AddLiteral("| where repositoryOwnerId == repositoryOwnerIdParam").AddLiteral("\n")
		ownerId := *queryOptions.Scope.OwnerId
		if version == versioning.V2 {
			params = params.AddLong("repositoryOwnerIdParam", ownerId)
		} else {
			params = params.AddString("repositoryOwnerIdParam", strconv.FormatInt(ownerId, 10))
		}
	} else if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_REPO {
		baseQueryBuilder = baseQueryBuilder.AddLiteral("| where repositoryOwnerId == repositoryOwnerIdParam and repositoryId == repositoryIdParam").AddLiteral("\n")
		ownerId := *queryOptions.Scope.OwnerId
		if version == versioning.V2 {
			params = params.AddLong("repositoryOwnerIdParam", ownerId)
		} else {
			params = params.AddString("repositoryOwnerIdParam", strconv.FormatInt(ownerId, 10))
		}
		repoId := *queryOptions.Scope.RepositoryId
		params = params.AddLong("repositoryIdParam", repoId)
	} else if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_ENTERPRISE {
		baseQueryBuilder = baseQueryBuilder.AddLiteral("| where repositoryOwnerId in (enterpriseOrgsParam)").AddLiteral("\n")
		if version == versioning.V2 {
			params = params.AddDynamic("enterpriseOrgsParam", queryOptions.Scope.EnterpriseOrgs)
		} else {
			ownerIds := utils.Map(queryOptions.Scope.EnterpriseOrgs, func(ownerId int64, _ int) string {
				return strconv.FormatInt(ownerId, 10)
			})
			params = params.AddDynamic("enterpriseOrgsParam", ownerIds)
		}
	}

	if aggregationQuery == nil {
		aggregationQuery = kql.New("")
	}

	return &KustoQueryBuilder{
		params:                   params,
		restrictBuilder:          restrictBuilder,
		baseQueryBuilder:         baseQueryBuilder,
		aggregationBuilder:       aggregationQuery,
		filtersBuilder:           kql.New(""),
		searchBuilder:            kql.New(""),
		orderByBuilder:           kql.New(""),
		pagingBuilder:            kql.New(""),
		summarizeBuilder:         kql.New(""),
		managementCommandBuilder: kql.New(""),
		countOnly:                countOnly,
	}
}

func NewKustoRepositoryNamesQueryBuilder(
	tableOrView string,
	aggregationQuery *kql.Builder,
	queryOptions QueryOptions) *KustoQueryBuilder {
	var restrictBuilder *kql.Builder

	if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_ORG {
		restrictBuilder = kql.New(`let RestrictedView = view () { `).AddUnsafe(tableOrView).AddLiteral(` | where owner_id == repositoryOwnerIdParam }; restrict access to (RestrictedView);`).AddLiteral("\n")
	} else if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_REPO {
		restrictBuilder = kql.New(`let RestrictedView = view () { `).AddUnsafe(tableOrView).AddLiteral(` | where owner_id == repositoryOwnerIdParam and id == repositoryIdParam }; restrict access to (RestrictedView);`).AddLiteral("\n")
	} else if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_ENTERPRISE {
		restrictBuilder = kql.New(`let RestrictedView = view () { `).AddUnsafe(tableOrView).AddLiteral(` | where owner_id in (enterpriseOrgsParam) }; restrict access to (RestrictedView);`).AddLiteral("\n")
	} else {
		return nil
	}

	baseQueryBuilder := kql.New("").AddTable("RestrictedView").AddLiteral("\n")
	params := kql.NewParameters()

	// this reads from the repo names table which always uses numerical owner id (unlike the other tables which user numerical in base and string in V2+ base)
	if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_ORG {
		baseQueryBuilder = baseQueryBuilder.AddLiteral("| where owner_id == repositoryOwnerIdParam").AddLiteral("\n")
		ownerId := *queryOptions.Scope.OwnerId
		params = params.AddLong("repositoryOwnerIdParam", ownerId)
	} else if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_REPO {
		baseQueryBuilder = baseQueryBuilder.AddLiteral("| where owner_id == repositoryOwnerIdParam and id == repositoryIdParam").AddLiteral("\n")
		ownerId := *queryOptions.Scope.OwnerId
		repoId := *queryOptions.Scope.RepositoryId
		params = params.AddLong("repositoryIdParam", repoId)
		params = params.AddLong("repositoryOwnerIdParam", ownerId)
	} else if queryOptions.Scope.ScopeType == proto.ScopeType_SCOPE_TYPE_ENTERPRISE {
		baseQueryBuilder = baseQueryBuilder.AddLiteral("| where owner_id in (enterpriseOrgsParam)").AddLiteral("\n")
		params = params.AddDynamic("enterpriseOrgsParam", queryOptions.Scope.EnterpriseOrgs)
	}

	if aggregationQuery == nil {
		aggregationQuery = kql.New("")
	}

	return &KustoQueryBuilder{
		params:                   params,
		restrictBuilder:          restrictBuilder,
		baseQueryBuilder:         baseQueryBuilder,
		aggregationBuilder:       aggregationQuery,
		filtersBuilder:           kql.New(""),
		searchBuilder:            kql.New(""),
		orderByBuilder:           kql.New(""),
		pagingBuilder:            kql.New(""),
		summarizeBuilder:         kql.New(""),
		managementCommandBuilder: kql.New(""),
		countOnly:                false,
	}
}

func NewKustoQueryBuilderNoTenant(tableOrView string, projectionFields []AllowedNoTenantField, allowCommandResults bool, aggregationQuery *kql.Builder) *KustoQueryBuilder {
	allowedTables := []AllowedTable{RestrictedView}
	if allowCommandResults {
		allowedTables = append(allowedTables, CommandResults)
	}

	restrictedTableStrings, err := utils.EnumsToStrings(allowedTables)
	if err != nil {
		log.WithError(err).Error("failed to convert allowed tables to strings")
		return nil
	}
	restrictedTablesQueryString := strings.Join(restrictedTableStrings, ", ")

	projectionFieldStrings, err := utils.EnumsToStrings(projectionFields)
	if err != nil {
		log.WithError(err).Error("failed to convert projection fields to strings")
		return nil
	}
	projectionFieldsQueryString := strings.Join(projectionFieldStrings, ", ")

	restrictBuilder := kql.New(`let RestrictedView = view () { `).AddUnsafe(tableOrView).AddLiteral(` | project-keep `).AddUnsafe(projectionFieldsQueryString).AddLiteral(` }; restrict access to (`).AddUnsafe(restrictedTablesQueryString).AddLiteral(");\n")

	if aggregationQuery == nil {
		aggregationQuery = kql.New("")
	}

	return &KustoQueryBuilder{
		restrictBuilder:          restrictBuilder,
		aggregationBuilder:       aggregationQuery,
		baseQueryBuilder:         kql.New(""),
		filtersBuilder:           kql.New(""),
		searchBuilder:            kql.New(""),
		orderByBuilder:           kql.New(""),
		pagingBuilder:            kql.New(""),
		summarizeBuilder:         kql.New(""),
		managementCommandBuilder: kql.New(""),
		params:                   kql.NewParameters(),
	}
}

func (qb *KustoQueryBuilder) SetOffsetLimit(val querybuilder.OffsetLimit) {
	pagingBuilder := kql.New("")
	if val.Offset == 0 {
		// offset is 0 so we only care about setting the limit, we don't care about paging
		pagingBuilder = pagingBuilder.AddLiteral("| limit sizeLimit").AddLiteral("\n")
		qb.SetParameter("sizeLimit", val.Limit)

	} else {
		// We currently abuse Kusto's row_number() to page through results on the query itself.
		// This is inefficient since Kusto has to re-perform the query each time,
		// but good enough for now until we potentially implement storing query results (and then paging through them) via
		// https://learn.microsoft.com/en-us/azure/data-explorer/kusto/management/stored-query-results
		// Note: We set row_number to be zero-indexed to match our twirp API and be less confusing
		pagingBuilder = pagingBuilder.AddLiteral("| extend row = row_number(0)").AddLiteral("\n").
			AddLiteral("| where row between (startRow .. endRow)").AddLiteral("\n").
			AddLiteral("| project-away row").AddLiteral("\n")

		qb.pagingBuilder = pagingBuilder
		qb.SetParameter("startRow", val.Offset)
		qb.SetParameter("endRow", val.Offset+val.Limit-1)
	}

	qb.pagingBuilder = pagingBuilder
}

func (qb *KustoQueryBuilder) SetParameter(name string, value interface{}) *KustoQueryBuilder {
	switch v := value.(type) {
	case string:
		qb.params = qb.params.AddString(name, v)
	case int:
		qb.params = qb.params.AddInt(name, int32(v))
	case int32:
		qb.params = qb.params.AddInt(name, v)
	case int64:
		qb.params = qb.params.AddLong(name, v)
	case uint:
		qb.params = qb.params.AddInt(name, int32(v))
	case uint32:
		qb.params = qb.params.AddInt(name, int32(v))
	case uint64:
		qb.params = qb.params.AddLong(name, int64(v))
	case float32:
		qb.params = qb.params.AddReal(name, float64(v))
	case float64:
		qb.params = qb.params.AddReal(name, float64(v))
	default:
		log.Error("unsupported parameter type", kvp.String(telemetry.OTelKeyName, name), kvp.String(telemetry.OTelKeyType, fmt.Sprintf("%T", v)))
	}

	return qb
}

func (qb *KustoQueryBuilder) SetOrderBy(orderBy []querybuilder.OrderBy) *KustoQueryBuilder {
	if len(orderBy) > 0 {
		orderByBuilder := kql.New("| order by ")
		for index, orderByItem := range orderBy {
			if index > 0 {
				orderByBuilder = orderByBuilder.AddLiteral(", ")
			}
			orderByBuilder.AddColumn(orderByItem.Field.String())
			if orderByItem.Direction == querybuilder.OrderByDirection_ASC {
				orderByBuilder = orderByBuilder.AddLiteral(" asc")
			} else {
				orderByBuilder = orderByBuilder.AddLiteral(" desc")
			}
		}

		qb.orderByBuilder = orderByBuilder.AddLiteral("\n")
	}

	return qb
}

func (qb *KustoQueryBuilder) SetFilters(filters []querybuilder.KustoModelFilter) {
	filtersBuilder := kql.New("")
	for filterIndex, filter := range filters {
		if filter.Field == "" {
			log.Warn("empty filter field")
			continue
		}

		if filter.Operator == proto.FilterOperator_FILTER_OPERATOR_UNKNOWN {
			log.Warn("invalid filter operator", kvp.String(telemetry.FilterOperatorKey, filter.Operator.String()))
			continue
		}

		if len(filter.Values) == 0 {
			log.Warn("empty filter values")
			continue
		}

		filtersBuilder = filtersBuilder.AddLiteral("| where ")

		if filter.Operator != proto.FilterOperator_FILTER_OPERATOR_LIST_CONTAINS && filter.Operator != proto.FilterOperator_FILTER_OPERATOR_NOT_LIST_CONTAINS {
			filtersBuilder = filtersBuilder.AddColumn(filter.Field.String())
		}

		// Add parameters in advance
		currentFilterParameterNames := make([]string, len(filter.Values))
		for valueIndex, value := range filter.Values {
			filterParameterName := fmt.Sprintf("filter%dValue%d", filterIndex, valueIndex)
			qb.SetParameter(filterParameterName, value)
			currentFilterParameterNames[valueIndex] = filterParameterName
		}

		switch filter.Operator {
		case proto.FilterOperator_FILTER_OPERATOR_EQUALS, proto.FilterOperator_FILTER_OPERATOR_NOT_EQUALS:
			if len(filter.Values) == 1 {
				if filter.Operator == proto.FilterOperator_FILTER_OPERATOR_EQUALS {
					if filter.Field.IsNumeric() {
						filtersBuilder = filtersBuilder.AddLiteral(" == ")
					} else {
						filtersBuilder = filtersBuilder.AddLiteral(" =~ ")
					}
				} else {
					if filter.Field.IsNumeric() {
						filtersBuilder = filtersBuilder.AddLiteral(" != ")
					} else {
						filtersBuilder = filtersBuilder.AddLiteral(" !~ ")
					}
				}

				filtersBuilder = filtersBuilder.AddColumn(currentFilterParameterNames[0])
			} else {
				if filter.Operator == proto.FilterOperator_FILTER_OPERATOR_EQUALS {
					if filter.Field.IsNumeric() {
						filtersBuilder = filtersBuilder.AddLiteral(" in ")
					} else {
						filtersBuilder = filtersBuilder.AddLiteral(" in~ ")
					}
				} else {
					if filter.Field.IsNumeric() {
						filtersBuilder = filtersBuilder.AddLiteral(" !in ")
					} else {
						filtersBuilder = filtersBuilder.AddLiteral(" !in~ ")
					}
				}

				filtersBuilder = filtersBuilder.AddLiteral("(")

				for i, parameterName := range currentFilterParameterNames {
					if i > 0 {
						filtersBuilder = filtersBuilder.AddLiteral(", ")
					}
					filtersBuilder = filtersBuilder.AddColumn(parameterName)
				}
				filtersBuilder = filtersBuilder.AddLiteral(")")
			}

		case proto.FilterOperator_FILTER_OPERATOR_CONTAINS:
			filtersBuilder = filtersBuilder.AddLiteral(" contains ").AddColumn(currentFilterParameterNames[0])

		case proto.FilterOperator_FILTER_OPERATOR_GREATER_THAN:
			filtersBuilder = filtersBuilder.AddLiteral(" > ").AddColumn(currentFilterParameterNames[0])

		case proto.FilterOperator_FILTER_OPERATOR_GREATER_THAN_OR_EQUAL:
			filtersBuilder = filtersBuilder.AddLiteral(" >= ").AddColumn(currentFilterParameterNames[0])

		case proto.FilterOperator_FILTER_OPERATOR_LESS_THAN:
			filtersBuilder = filtersBuilder.AddLiteral(" < ").AddColumn(currentFilterParameterNames[0])

		case proto.FilterOperator_FILTER_OPERATOR_LESS_THAN_OR_EQUAL:
			filtersBuilder = filtersBuilder.AddLiteral(" <= ").AddColumn(currentFilterParameterNames[0])

		case proto.FilterOperator_FILTER_OPERATOR_BETWEEN:
			if len(filter.Values) != 2 {
				log.Warn("invalid number of values for 'between' filter")
				continue
			}
			filtersBuilder = filtersBuilder.
				AddLiteral(" between (").
				AddColumn(currentFilterParameterNames[0]).
				AddLiteral(" .. ").
				AddColumn(currentFilterParameterNames[1]).
				AddLiteral(")")
		case proto.FilterOperator_FILTER_OPERATOR_LIST_CONTAINS, proto.FilterOperator_FILTER_OPERATOR_NOT_LIST_CONTAINS:
			filtersBuilder = filtersBuilder.AddLiteral("array_length(set_intersect(").AddColumn(filter.Field.String()).AddLiteral(", dynamic([")

			for i, parameterName := range currentFilterParameterNames {
				if i > 0 {
					filtersBuilder = filtersBuilder.AddLiteral(", ")
				}
				filtersBuilder = filtersBuilder.AddColumn(parameterName)
			}

			filtersBuilder = filtersBuilder.AddLiteral("])))")

			if filter.Operator == proto.FilterOperator_FILTER_OPERATOR_LIST_CONTAINS {
				filtersBuilder = filtersBuilder.AddLiteral(" > 0")
			} else {
				// not contains
				filtersBuilder = filtersBuilder.AddLiteral(" == 0")
			}
		default:
			log.Error("missing filter operator implementation", kvp.String(telemetry.FilterOperatorKey, filter.Operator.String()))
			continue
		}

		filtersBuilder = filtersBuilder.AddLiteral("\n")
	}

	qb.filtersBuilder = filtersBuilder
}

func (qb *KustoQueryBuilder) SetSearch(search Search) {
	searchBuilder := kql.New("")
	searchText := ""
	if search.Search != nil {
		searchText = *search.Search
	}

	searchBuilder = searchBuilder.AddLiteral("| where ").AddColumn(search.Column).AddLiteral(" contains searchQuery").AddLiteral("\n")

	if searchText != "" {
		// set weight so exact match -> starts with -> contains
		// | extend weight = iff(search.Column == searchText, 100, iff(search.Column startswith searchText, 10, 1))
		searchBuilder = searchBuilder.AddLiteral("| extend weight = iff(").AddColumn(search.Column).AddLiteral(" == ").
			AddString(searchText).AddLiteral(", 100, iff(").AddColumn(search.Column).AddLiteral(" startswith ").AddString(searchText).
			AddLiteral(", 10, 1))").AddLiteral("\n")
		searchBuilder = searchBuilder.AddLiteral("| summarize by ").AddColumn(search.Column).AddLiteral(", weight").AddLiteral("\n")
		searchBuilder = searchBuilder.AddLiteral("| order by weight desc,").AddColumn(search.Column).AddLiteral(" asc").AddLiteral("\n")
	} else {
		// empty search so return top by alphabetical.
		searchBuilder = searchBuilder.AddLiteral("| summarize by ").AddColumn(search.Column).AddLiteral("\n")
		searchBuilder = searchBuilder.AddLiteral("| order by ").AddColumn(search.Column).AddLiteral(" asc").AddLiteral("\n")
	}
	searchBuilder.AddLiteral("| project-rename item = ").AddColumn(search.Column).AddLiteral("\n")
	searchBuilder.AddLiteral("| project item").AddLiteral("\n")

	qb.SetParameter("searchQuery", searchText)

	qb.searchBuilder = searchBuilder
}

func (qb *KustoQueryBuilder) SetSummarize(summarize *kql.Builder) {
	qb.summarizeBuilder = summarize
}

func (qb *KustoQueryBuilder) SetShowMaterializedViewCommand(tableOrView string) {
	qb.managementCommandBuilder = kql.New(".show materialized-view ").AddUnsafe(tableOrView).AddLiteral(";\n")
}

func (qb *KustoQueryBuilder) Build() query {
	// Note: kql has no other way to merge multiple builders besides AddUnsafe,
	// but each individual builder has been constructed safely
	queryBuilder := kql.FromBuilder(qb.managementCommandBuilder).
		AddUnsafe(qb.restrictBuilder.String())

	if qb.params.Count() > 0 {
		queryBuilder = queryBuilder.AddUnsafe(qb.params.ToDeclarationString()).AddLiteral("\n") // Restrict "kills" the query parameter declaration at the top, so we need to repeat it
	}

	queryBuilder = queryBuilder.AddUnsafe(qb.baseQueryBuilder.String()).
		AddUnsafe(qb.aggregationBuilder.String()).
		AddUnsafe(qb.filtersBuilder.String())
	if qb.countOnly {
		queryBuilder = queryBuilder.AddLiteral("| count").AddLiteral("\n")
	} else {
		queryBuilder = queryBuilder.
			AddUnsafe(qb.orderByBuilder.String()).
			AddUnsafe(qb.searchBuilder.String()).
			AddUnsafe(qb.pagingBuilder.String()).
			AddUnsafe(qb.summarizeBuilder.String())
	}

	return newQuery(queryBuilder, qb.params)
}
