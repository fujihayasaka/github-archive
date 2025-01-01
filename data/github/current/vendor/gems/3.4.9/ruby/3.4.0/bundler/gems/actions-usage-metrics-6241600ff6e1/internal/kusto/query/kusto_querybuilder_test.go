package query

import (
	"strings"
	"testing"
	"time"

	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/querybuilder"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/stretchr/testify/assert"
)

const TestTable = "TestTable"
const expectedRestrictedClause = "let RestrictedView = view () { TestTable | where repositoryOwnerId == repositoryOwnerIdParam }; restrict access to (RestrictedView);"
const expectedRestrictedClauseRepo = "let RestrictedView = view () { TestTable | where repositoryOwnerId == repositoryOwnerIdParam and repositoryId == repositoryIdParam }; restrict access to (RestrictedView);"
const expectedRestrictedClauseEnterprise = "let RestrictedView = view () { TestTable | where repositoryOwnerId in (enterpriseOrgsParam) }; restrict access to (RestrictedView);"

var Version = versioning.ActiveProjectionVersion_Api
var TeststartDayParam = time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
var TestendDayParam = time.Date(2024, 1, 2, 0, 0, 0, 0, time.UTC)
var queryOptions = QueryOptions{
	Scope:         utils.GetScopeFromOwnerId(123),
	StartDay:      &TeststartDayParam,
	EndDay:        &TestendDayParam,
	Version:       &Version,
	GetTotalCount: true,
}

var queryOptionsRepo = QueryOptions{
	Scope:         utils.GetScopeFromRepo(123, 1),
	StartDay:      &TeststartDayParam,
	EndDay:        &TestendDayParam,
	Version:       &Version,
	GetTotalCount: true,
}

var queryOptionsEnterprise = QueryOptions{
	Scope:         utils.GetScopeFromEnterpriseOrgs([]int64{9919, 33435682}), // gh and bbq-beets
	StartDay:      &TeststartDayParam,
	EndDay:        &TestendDayParam,
	Version:       &Version,
	GetTotalCount: true,
}

// Tests that the "core" part of each query is the same (ignoring parameter declaration string and leading/trailing whitespace on each line).
func AssertEqual(t *testing.T, expected string, actual query) {
	// Test that all queries must have the same restrict statement for multi-tenancy safety
	expected = expectedRestrictedClause + "\n" + expected
	assert.Equal(t, trimEachLine(expected), trimEachLine(actual.Query().String()))
}

func AssertEqualRepo(t *testing.T, expected string, actual query) {
	// Test that all queries must have the same restrict statement for multi-tenancy safety
	expected = expectedRestrictedClauseRepo + "\n" + expected
	assert.Equal(t, trimEachLine(expected), trimEachLine(actual.Query().String()))
}

func AssertEqualEnterprise(t *testing.T, expected string, actual query) {
	// Test that all queries must have the same restrict statement for multi-tenancy safety
	expected = expectedRestrictedClauseEnterprise + "\n" + expected
	assert.Equal(t, trimEachLine(expected), trimEachLine(actual.Query().String()))
}

func trimEachLine(s string) string {
	lines := strings.Split(s, "\n")
	newLines := make([]string, 0, len(lines))
	for _, line := range lines {
		newLine := strings.TrimSpace(line)
		// Ignore the parameter declaration string. We would test it, but the implementation in the Kusto library produces non-deterministic ordering :-(
		if newLine != "" && strings.Index(line, "declare query_parameters") == -1 {
			newLines = append(newLines, newLine)
		}
	}

	return strings.Join(newLines, "\n")
}

func TestKustoFilter(t *testing.T) {
	var tests = []struct {
		name                    string
		filters                 []querybuilder.KustoModelFilter
		expectedQueryText       string
		expectedQueryParameters map[string]string
	}{
		{
			name: "Equality",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_EQUALS,
					Values:   []any{"bar"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam 
				 | where fooVal =~ filter0Value0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `"bar"`,
			},
		},
		{
			name: "MultipleEquality",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_EQUALS,
					Values:   []any{"bar", "baz"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal in~ (filter0Value0, filter0Value1)
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `"bar"`,
				"filter0Value1":          `"baz"`,
			},
		},
		{
			name: "Inequality",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_NOT_EQUALS,
					Values:   []any{"bar"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal !~ filter0Value0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `"bar"`,
			},
		},
		{
			name: "MultipleInequality",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_NOT_EQUALS,
					Values:   []any{"bar", "baz"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal !in~ (filter0Value0, filter0Value1)
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `"bar"`,
				"filter0Value1":          `"baz"`,
			},
		},
		{
			name: "Contains",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_CONTAINS,
					Values:   []any{"bar"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal contains filter0Value0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `"bar"`,
			},
		},
		{
			name: "GreaterThan",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_GREATER_THAN,
					Values:   []any{2},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal > filter0Value0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          "int(2)",
			},
		},
		{
			name: "GreaterThanOrEqual",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_GREATER_THAN_OR_EQUAL,
					Values:   []any{2},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal >= filter0Value0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          "int(2)",
			},
		},
		{
			name: "LessThan",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_LESS_THAN,
					Values:   []any{2},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal < filter0Value0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          "int(2)",
			},
		},
		{
			name: "LessThanOrEqual",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_LESS_THAN_OR_EQUAL,
					Values:   []any{2},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal <= filter0Value0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          "int(2)",
			},
		},
		{
			name: "Between",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_BETWEEN,
					Values:   []any{2, 4},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam
				 | where fooVal between (filter0Value0 .. filter0Value1)
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				 `,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          "int(2)",
				"filter0Value1":          "int(4)",
			},
		},
		{
			name: "List Contains",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_LIST_CONTAINS,
					Values:   []any{"bar"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam 
				 | where array_length(set_intersect(fooVal, filter0Value0)) > 0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `dynamic(["bar"])`,
			},
		},
		{
			name: "List Contains Multiple",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_LIST_CONTAINS,
					Values:   []any{"bar", "zee"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam 
				 | where array_length(set_intersect(fooVal, filter0Value0)) > 0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `dynamic(["bar","zee"])`,
			},
		},
		{
			name: "List Not Contains",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_NOT_LIST_CONTAINS,
					Values:   []any{"bar"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam 
				 | where array_length(set_intersect(fooVal, filter0Value0)) == 0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `dynamic(["bar"])`,
			},
		},
		{
			name: "List Not Contains Multiple",
			filters: []querybuilder.KustoModelFilter{
				{
					Field:    "fooVal",
					Operator: proto.FilterOperator_FILTER_OPERATOR_NOT_LIST_CONTAINS,
					Values:   []any{"bar", "zee"},
				},
			},
			expectedQueryText: `
				let results = materialize(RestrictedView
				 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
				 | where repositoryOwnerId == repositoryOwnerIdParam 
				 | where array_length(set_intersect(fooVal, filter0Value0)) == 0
				);
				results
				| as ResultsTable;
				results
				| count 
				| as CountTable
				`,
			expectedQueryParameters: map[string]string{
				"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
				"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
				"repositoryOwnerIdParam": "\"123\"",
				"filter0Value0":          `dynamic(["bar","zee"])`,
			},
		},
	}

	// Execute tests
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			v := versioning.ActiveProjectionVersion_Api
			queryOptions := QueryOptions{
				Scope:         utils.GetScopeFromOwnerId(123),
				StartDay:      &TeststartDayParam,
				EndDay:        &TestendDayParam,
				Version:       &v,
				GetTotalCount: true,
			}
			qb := NewKustoQueryBuilder(TestTable, nil, queryOptions)
			qb.SetFilters(tt.filters)
			result := qb.Build()
			AssertEqual(t, tt.expectedQueryText, result)
			assert.Equal(t, tt.expectedQueryParameters, result.Parameters().ToParameterCollection())
		})
	}
}

func TestKustoAggregationQuery(t *testing.T) {
	aggregationBuilder := kql.New(`| summarize count() by repositoryOwnerId`).AddLiteral("\n")

	qb := NewKustoQueryBuilder(TestTable, aggregationBuilder, queryOptions)

	query := qb.Build()
	AssertEqual(t, `
		let results = materialize(RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId == repositoryOwnerIdParam
		 | summarize count() by repositoryOwnerId
		);
		results
		| as ResultsTable;
		results
		| count 
		| as CountTable
		`, query)
	assert.Equal(t, map[string]string{
		"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
		"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
		"repositoryOwnerIdParam": "\"123\"",
	}, query.Parameters().ToParameterCollection())
}

func TestKustoOffsetLimit(t *testing.T) {
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptions)
	qb.SetOffsetLimit(querybuilder.OffsetLimit{
		Offset: 10,
		Limit:  20,
	})
	query := qb.Build()
	AssertEqual(t, `
		let results = materialize(RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId == repositoryOwnerIdParam
		);
		results
		| extend row = row_number(0)
		| where row between (startRow .. endRow)
		| project-away row
		| as ResultsTable;
		results
		| count 
		| as CountTable
		`, query)
	assert.Equal(t, map[string]string{
		"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
		"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
		"repositoryOwnerIdParam": "\"123\"",
		"startRow":               "long(10)",
		"endRow":                 "long(29)",
	}, query.Parameters().ToParameterCollection())
}

func TestKustoOrderByAsc(t *testing.T) {
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptions)
	orderby := []querybuilder.OrderBy{{Field: "fooVal", Direction: querybuilder.OrderByDirection_ASC}}
	qb.SetOrderBy(orderby)
	query := qb.Build()
	AssertEqual(t, `
		let results = materialize(RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId == repositoryOwnerIdParam
		);
		results
		| order by fooVal asc
		| as ResultsTable;
		results
		| count 
		| as CountTable
		`, query)
}

func TestKustoOrderByDesc(t *testing.T) {
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptions)
	orderby := []querybuilder.OrderBy{{Field: "fooVal", Direction: querybuilder.OrderByDirection_DESC}}
	qb.SetOrderBy(orderby)
	query := qb.Build()
	AssertEqual(t, `
		let results = materialize(RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId == repositoryOwnerIdParam
		);
		results
		| order by fooVal desc
		| as ResultsTable;
		results
		| count 
		| as CountTable
		`, query)
}

func TestKustoComplexQuery(t *testing.T) {
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptions)
	qb.SetFilters([]querybuilder.KustoModelFilter{
		{
			Field:    "fooVal",
			Operator: proto.FilterOperator_FILTER_OPERATOR_EQUALS,
			Values:   []any{"bar"},
		},
		{
			Field:    "barVal",
			Operator: proto.FilterOperator_FILTER_OPERATOR_NOT_EQUALS,
			Values:   []any{"baz", "qux"},
		},
		{
			Field:    "bazVal",
			Operator: proto.FilterOperator_FILTER_OPERATOR_BETWEEN,
			Values:   []any{100, 200},
		},
	})
	qb.SetOffsetLimit(querybuilder.OffsetLimit{Offset: 10, Limit: 20})
	orderby := []querybuilder.OrderBy{{Field: "fooVal", Direction: querybuilder.OrderByDirection_DESC}}
	qb.SetOrderBy(orderby)
	query := qb.Build()

	AssertEqual(t, `
		let results = materialize(RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId == repositoryOwnerIdParam
		 | where fooVal =~ filter0Value0
		 | where barVal !in~ (filter1Value0, filter1Value1)
		 | where bazVal between (filter2Value0 .. filter2Value1)
		);
		results
		| order by fooVal desc
		| extend row = row_number(0)
		| where row between (startRow .. endRow)
		| project-away row
		| as ResultsTable;
		results
		| count 
		| as CountTable
		`, query)

	assert.Equal(t, map[string]string{
		"startDayParam":          `datetime(2024-01-01T00:00:00Z)`,
		"endDayParam":            `datetime(2024-01-02T00:00:00Z)`,
		"repositoryOwnerIdParam": "\"123\"",
		"filter0Value0":          `"bar"`,
		"filter1Value0":          `"baz"`,
		"filter1Value1":          `"qux"`,
		"filter2Value0":          `int(100)`,
		"filter2Value1":          `int(200)`,
		"startRow":               "long(10)",
		"endRow":                 "long(29)",
	}, query.Parameters().ToParameterCollection())
}

func TestKustoUnknownFilterOperatorIgnoresFilter(t *testing.T) {
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptions)
	qb.SetFilters([]querybuilder.KustoModelFilter{
		{
			Field:    "fooVal",
			Operator: proto.FilterOperator_FILTER_OPERATOR_UNKNOWN,
			Values:   []any{"bar"},
		},
	})
	query := qb.Build()
	AssertEqual(t, `
		let results = materialize(RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId == repositoryOwnerIdParam
		);
		results
		| as ResultsTable;
		results
		| count 
		| as CountTable
		`, query)
}

func TestQueryIsReadonly(t *testing.T) {
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptions)
	query := qb.Build()
	originalQuery := query.Query().String()
	assert.Panics(t, func() { query.Query().AddLiteral(" | extend foo = bar") })
	newQuery := query.Query().String()
	assert.Equal(t, originalQuery, newQuery)
}

func TestNewKustoQueryBuilderNoTenant(t *testing.T) {
	qb := NewKustoQueryBuilderNoTenant(TestTable, []AllowedNoTenantField{CompletedAt}, false, kql.New("RestrictedView | take 1"))
	query := qb.Build()
	assert.Equal(t,
		"let RestrictedView = view () { TestTable | project-keep completed_at }; restrict access to (RestrictedView);\nRestrictedView | take 1",
		query.Query().String())
}

func TestRepoLevel(t *testing.T) {
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptionsRepo)

	query := qb.Build()
	AssertEqualRepo(t, `
		let results = materialize(RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId == repositoryOwnerIdParam and repositoryId == repositoryIdParam
		);
		results
		| as ResultsTable;
		results
		| count 
		| as CountTable
		`, query)
}

func TestEnterpriseLevel(t *testing.T) {
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptionsEnterprise)

	query := qb.Build()
	AssertEqualEnterprise(t, `
		let results = materialize(RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId in (enterpriseOrgsParam)
		);
		results
		| as ResultsTable;
		results
		| count 
		| as CountTable
		`, query)
}

func TestRepoNamesQuery(t *testing.T) {
	queryOptions := QueryOptions{
		Scope:         utils.GetScopeFromOwnerId(9919), // gh and bbq-beets
		StartDay:      &TeststartDayParam,
		EndDay:        &TestendDayParam,
		Version:       &Version,
		GetTotalCount: false,
	}
	qb := NewKustoRepositoryNamesQueryBuilder(TestTable, nil, queryOptions)

	query := qb.Build()
	assert.Equal(t, trimEachLine(
		`
		let RestrictedView = view () { TestTable | where owner_id == repositoryOwnerIdParam }; restrict access to (RestrictedView);
		RestrictedView
		| where owner_id == repositoryOwnerIdParam
		| as ResultsTable
	`), trimEachLine(query.Query().String()))
}

func TestOrgNamesQuery(t *testing.T) {
	queryOptions := QueryOptions{
		Scope:         utils.GetScopeFromEnterpriseOrgs([]int64{9919, 33435682}), // gh and bbq-beets
		StartDay:      &TeststartDayParam,
		EndDay:        &TestendDayParam,
		Version:       &Version,
		GetTotalCount: false,
	}
	qb := NewKustoOrgNamesQueryBuilder(TestTable, nil, queryOptions)

	query := qb.Build()
	assert.Equal(t, trimEachLine(
		`
		let RestrictedView = view () { TestTable | where id in (enterpriseOrgsParam) and type == "Organization" }; restrict access to (RestrictedView);
		RestrictedView
		| where id in (enterpriseOrgsParam) and type == "Organization"
		| as ResultsTable
	`), trimEachLine(query.Query().String()))
}

func TestQueryWithoutCount(t *testing.T) {
	queryOptions := QueryOptions{
		Scope:         utils.GetScopeFromOwnerId(9919), // gh and bbq-beets
		StartDay:      &TeststartDayParam,
		EndDay:        &TestendDayParam,
		Version:       &Version,
		GetTotalCount: false,
	}
	qb := NewKustoQueryBuilder(TestTable, nil, queryOptions)

	query := qb.Build()
	AssertEqual(t, `
		RestrictedView
		 | where timestamp between (startofday(startDayParam) .. endofday(endDayParam))
		 | where repositoryOwnerId == repositoryOwnerIdParam
		 | as ResultsTable
		`, query)
}
