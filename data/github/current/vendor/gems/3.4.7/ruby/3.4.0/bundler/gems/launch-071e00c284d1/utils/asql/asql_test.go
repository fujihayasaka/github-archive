package asql

import (
	"context"
	"database/sql"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/go-sql-driver/mysql"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"

	"github.com/github/go-queryannotations"
	"github.com/github/go-queryannotations/annotation"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/testutils"
)

type asqlSuite struct {
	suite.Suite
	conn    *sql.DB
	stats   *statter.MockStatter
	logs    testutils.RecordingLogger
	asql    *SQL
	breaker *circuit.Breaker
}

func TestASQL(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(asqlSuite))
}

func (s *asqlSuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	_, err = conn.Exec(`
		DROP TABLE IF EXISTS asql_test
	`)
	s.Require().NoError(err)
	_, err = conn.Exec(`
		CREATE TABLE asql_test (
		    id int PRIMARY KEY,
		    name varchar(30)
		)
	`)
	s.Require().NoError(err)
	_, err = conn.Exec(`
		INSERT INTO asql_test (
		  id,
		  name
		)
		VALUES
			(1, "one"),
			(2, "two")
	`)
	s.Require().NoError(err)
	s.conn = conn
}

func (s *asqlSuite) SetupTest() {
	s.logs = testutils.NewRecordingLogger()
	s.stats = &statter.MockStatter{}
	s.stats.On("Histogram", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
	s.stats.On("Distribution", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
	s.breaker = testutils.NewNoopBreaker()
	s.asql = New(s.conn, s.logs.Logger, s.stats, s.breaker, "asql")
}

func (s *asqlSuite) TestBreaker() {
	s.expectTiming()

	s.breaker.Break()
	_, err := s.asql.ExecContext(context.Background(), `select 1`)
	s.Require().EqualError(err, "act_query: breaker open")
}

func (s *asqlSuite) TestWrapsOperationWithNamedSpan() {
	s.expectTiming()

	sn := testutils.CollectFinishedSpanNames(func() {
		_, err := s.asql.ExecContextWith(context.Background(), `select ?`, WithName("TestOp"), 1)
		s.Require().NoError(err)
	})

	s.Contains(sn, "asql/(*SQL).TestOp")
}

func (s *asqlSuite) TestExecContextWithAnnotatesQuery() {
	s.expectTiming()

	sps := testutils.CollectFinishedSpans(func() {
		_, err := s.asql.ExecContextWith(context.Background(), `select ?`, WithName("TestOp"), 1)
		s.Require().NoError(err)
	})

	s.True(
		s.findSpanWithAttribute(sps, "db.Exec", "db.statement", "/*name:TestOp,application:launch,deployed_to:*/ select ?"),
		"db.Exec span not found",
	)
}

func (s *asqlSuite) TestQueryContextWithAnnotatesQuery() {
	s.expectTiming()

	sps := testutils.CollectFinishedSpans(func() {
		rows, err := s.asql.QueryContextWith(context.Background(), `select ?`, WithName("TestOp"), 1)
		defer rows.Close()
		s.Require().NoError(err)
		s.Require().NoError(rows.Err())
	})

	s.True(
		s.findSpanWithAttribute(sps, "db.Query", "db.statement", "/*name:TestOp,application:launch,deployed_to:*/ select ?"),
		"db.Query span not found",
	)
}

func (s *asqlSuite) TestAnnotatesQueryWithJobID() {
	s.expectTiming()

	sps := testutils.CollectFinishedSpans(func() {
		ctx := context.Background()
		ctx = queryannotations.WithQueryAnnotations(ctx, annotation.JobID("job-id"))

		rows, err := s.asql.QueryContextWith(ctx, `select ?`, WithName("TestOp"), 1)
		defer rows.Close()
		s.Require().NoError(err)
		s.Require().NoError(rows.Err())
	})

	s.True(
		s.findSpanWithAttribute(sps, "db.Query", "db.statement", "/*name:TestOp,application:launch,deployed_to:,job_id:job-id*/ select ?"),
		"db.Query span not found",
	)
}

func (s *asqlSuite) findSpanWithAttribute(spans tracetest.SpanStubs, spanName, attributeName, attributeValue string) bool {
	found := false

	for _, span := range spans {
		if span.Name == spanName {
			for _, a := range span.Attributes {
				if a.Key == attribute.Key(attributeName) {
					s.Equal(attributeValue, a.Value.AsString())
					found = true
				}
			}
		}
	}

	return found
}

func (s *asqlSuite) TestWrapsOpWithDefaultNamedSpanIfNotProvided() {
	s.expectTiming()

	sn := testutils.CollectFinishedSpanNames(func() {
		_, err := s.asql.ExecContext(context.Background(), `select 1`)
		s.Require().NoError(err)
	})

	s.Contains(sn, "asql/(*SQL).act_query_unknown")
}

func (s *asqlSuite) TestExecContextOptions() {
	s.expectTiming()
	_, err := s.asql.ExecContextWith(context.Background(), `select ?`, WithName("TestOp"), 1)
	s.Require().NoError(err)
	s.Contains(s.logs.String(), `operation=TestOp`)
}

func (s *asqlSuite) TestQueryContextOptions() {
	s.expectTiming()
	rows, err := s.asql.QueryContextWith(context.Background(), `select ?`, WithName("TestOp"), "test-value")
	s.Require().NoError(err)
	s.Require().NoError(rows.Err())
	defer rows.Close()
	s.Contains(s.logs.String(), `operation=TestOp`)
	s.Require().True(rows.Next())
	var v string
	s.Require().NoError(rows.Scan(&v))
	s.Equal("test-value", v)
}

func (s *asqlSuite) TestScanWithOptions() {
	s.expectTiming()
	var scannedName string
	err := s.asql.QueryScanWith(context.Background(), `select ?`, WithName("TestOp"),
		Params("test-value-2"),
		&scannedName)
	s.Require().NoError(err)
	s.Contains(s.logs.String(), `operation=TestOp`)
	s.Equal("test-value-2", scannedName)
}

func (s *asqlSuite) TestTimer() {
	s.stats.On("Timing", mock.Anything, "act_query.time", mock.MatchedBy(func(tags statter.Tags) bool {
		s.Equal(statter.Tags{"operation": "act_query_unknown"}, tags)
		return true
	}), mock.MatchedBy(func(d time.Duration) bool {
		return d > 0
	})).Return()

	_, err := s.asql.ExecContext(context.Background(), `SELECT 1`)
	s.Require().NoError(err)
}

func (s *asqlSuite) TestLogging() {
	s.expectTiming()

	_, err := s.asql.ExecContextWith(context.Background(), `select 1`, WithName("TestOp"))
	s.Require().NoError(err)
	s.Contains(s.logs.String(), `Body=act_query`)
	s.Contains(s.logs.String(), `operation=TestOp`)
}

func (s *asqlSuite) TestErrorLogging() {
	s.expectTiming()

	_, err := s.asql.ExecContext(context.Background(), `not sql`)
	s.Require().Error(err)
	s.Contains(s.logs.String(), `error="Error 1064 (42000): You have an error in your SQL syntax;`)
}

func (s *asqlSuite) TestScan() {
	s.expectTiming()
	var name string
	var id int
	err := s.asql.QueryScan(context.Background(), `SELECT name, id FROM asql_test WHERE id = ?`,
		Params(1),
		&name,
		&id)

	s.Require().NoError(err)
	s.Equal("one", name)
	s.Equal(1, id)
}

func (s *asqlSuite) TestScanWithNoRowsShouldNotLog() {
	s.expectTiming()
	var name string
	var id int
	err := s.asql.QueryScan(context.Background(), `SELECT name, id FROM asql_test WHERE id = ?`,
		Params(3),
		&name,
		&id)

	s.Require().Error(err)
	s.NotContains(s.logs.String(), `error="no rows in result set`)
}

func (s *asqlSuite) TestScanWith() {
	s.expectTiming()
	var name string
	var id int
	err := s.asql.QueryScanWith(context.Background(), `SELECT name, id FROM asql_test WHERE id = ?`,
		WithName("TestScan"),
		Params(1),
		&name,
		&id)

	s.Require().NoError(err)
	s.Equal("one", name)
	s.Equal(1, id)
}

func (s *asqlSuite) TestReadRetriesServerShutdownErrorsUntilExhaustion() {
	s.expectTiming()
	operationName := "TestServerShutdownRetry"
	for i := 1; i <= maximumReadRetries; i++ {
		s.stats.EXPECT().Counter(context.Background(), metrickeys.ServerShutdownRetry, statter.Tags{
			metrickeys.OperationName: operationName,
			"attempt":                strconv.Itoa(i),
		}, int64(1))
	}
	err := s.asql.read(context.Background(), `SELECT name, id FROM asql_test WHERE id = 1`,
		WithName(operationName),
		func(sql string) error {
			return &mysql.MySQLError{
				Number:  mysqldb.ServerShutdownErrorCode,
				Message: "Server shutdown in progress",
			}
		},
	)
	s.Require().Error(err)
	s.Contains(s.logs.String(), `error="Error 1053: Server shutdown in progress`)
	s.Contains(s.logs.String(), `"retrying database operation due to server shutdown error"`)
}

func (s *asqlSuite) TestReadRetriesServerShutdownErrorsWithSuccess() {
	s.expectTiming()
	operationName := "TestServerShutdownRetry"
	for i := 1; i < maximumReadRetries; i++ {
		s.stats.EXPECT().Counter(context.Background(), metrickeys.ServerShutdownRetry, statter.Tags{
			metrickeys.OperationName: operationName,
			"attempt":                strconv.Itoa(i),
		}, int64(1))
	}
	attempt := 1
	err := s.asql.read(context.Background(), `SELECT name, id FROM asql_test WHERE id = 1`,
		WithName(operationName),
		func(sql string) error {
			if attempt%3 == 0 {
				return nil
			}
			attempt++
			return &mysql.MySQLError{
				Number:  mysqldb.ServerShutdownErrorCode,
				Message: "Server shutdown in progress",
			}
		},
	)
	s.Require().NoError(err)
	s.Contains(s.logs.String(), `error="Error 1053: Server shutdown in progress`)
	s.Contains(s.logs.String(), `"retrying database operation due to server shutdown error"`)
}

func (s *asqlSuite) expectTiming() {
	s.stats.EXPECT().Timing(mock.Anything, "act_query.time", mock.Anything, mock.Anything).Return()
}

func TestOptionsDefault(t *testing.T) {
	cfg := configFromOptions(nil)
	name := cfg.opName()
	assert.Equal(t, "act_query_unknown", name)
}

func TestOptionsWithName(t *testing.T) {
	cfg := configFromOptions(WithName("testOp"))
	name := cfg.opName()
	assert.Equal(t, "testOp", name)
}

func TestOptionsWithMultiple(t *testing.T) {
	cfg := configFromOptions(With(WithName("testOp")))
	name := cfg.opName()
	assert.Equal(t, "testOp", name)
}

func init() {
	testutils.EnsureGlobalTracerIsMocked()
}
