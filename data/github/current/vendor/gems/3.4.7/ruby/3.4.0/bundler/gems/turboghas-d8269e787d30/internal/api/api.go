// Package api contains the external Twirp interface.
package api

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/api/ctes"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/proto"
	"github.com/simon-engledew/sqlh"
	"github.com/twitchtv/twirp"
)

var SQL = sqlh.SQL

func init() {
	if fromctx.IsTest {
		SQL = sqlh.DebugSQL
	}
}

type handler struct {
	db mysql_dual.QueryDB
}

func NewAdvancedSecurityAPI(db mysql_dual.QueryDB) proto.AdvancedSecurityAPI {
	return &handler{
		db: db,
	}
}

func check(expr sqlh.Expr) {
	if !fromctx.IsTest {
		return
	}
	if strings.Contains(expr.Statement, "cte_contributions") {
		if !strings.Contains(expr.Statement, ctes.BillableUsers.Statement) {
			panic("contributions query did not contain a billable users check")
		}
	}
}

func (h *handler) QueryRow(ctx context.Context, expr sqlh.Expr) *sql.Row {
	check(expr)
	then := time.Now()
	row := expr.QueryRowContext(ctx, h.db)
	if row.Err() == nil {
		fromctx.QueryReporter.Report(ctx, expr.Statement, time.Since(then), 1)
	}
	return row
}

type rowsReporter struct {
	*sql.Rows
	count    int64
	duration time.Duration
	query    string
	ctx      context.Context
}

func (rr *rowsReporter) Next() bool {
	if rr.Rows.Next() {
		atomic.AddInt64(&rr.count, 1)
		return true
	}
	return false
}

func (rr *rowsReporter) Close() error {
	fromctx.QueryReporter.Report(rr.ctx, rr.query, rr.duration, rr.count)
	return rr.Rows.Close()
}

func (h *handler) Query(ctx context.Context, expr sqlh.Expr) (sqlh.Rows, error) {
	check(expr)
	then := time.Now()
	rows, err := expr.QueryContext(ctx, h.db)
	if err != nil {
		return rows, err
	}
	return &rowsReporter{
		Rows:     rows,
		duration: time.Since(then),
		query:    expr.Statement,
		ctx:      ctx,
	}, err
}

// rewriteInvalidConnection returns an Unavailable status if the database connection went away so that clients can retry
func rewriteInvalidConnection(fn twirp.Method) twirp.Method {
	return func(ctx context.Context, request any) (any, error) {
		resp, err := fn(ctx, request)
		if mysql_dual.IsTransientError(err) {
			err = twirp.NewError(twirp.Unavailable, "invalid connection")
		}
		return resp, err
	}
}

type entityRequest interface {
	GetEntityId() uint64
	GetEntityType() v1.EntityType
}

var _ entityRequest = &proto.GetSummaryRequest{}

// addEntityToError adds KVP fields for the current request entity to error if available.
func addEntityToError(fn twirp.Method) twirp.Method {
	return func(ctx context.Context, request any) (any, error) {
		resp, err := fn(ctx, request)
		if err != nil {
			if entityReq, ok := request.(entityRequest); ok {
				err = fields.Error(err,
					kvp.Uint64("turboghas.entity_id", entityReq.GetEntityId()),
					kvp.String("turboghas.entity_type", entityReq.GetEntityType().String()),
				)
			}
		}
		return resp, err
	}
}

func New(db *mysql_dual.Connection, opts ...any) http.Handler {
	return proto.NewAdvancedSecurityAPIServer(NewAdvancedSecurityAPI(db.Replica), append(opts, twirp.WithServerInterceptors(
		rewriteInvalidConnection,
		addEntityToError,
	))...)
}

func GetLimit[T interface{ GetLimit() N }, N ~uint32 | int32](req T, defaultValue, maxValue N) (N, error) {
	limit := req.GetLimit()
	// a negative limit can be used to get a count without returning any data
	if limit < 0 {
		return 0, nil
	}
	if limit == 0 {
		return defaultValue, nil
	}
	if limit > maxValue {
		return limit, fmt.Errorf("must be less than or equal to %d", maxValue)
	}
	return limit, nil
}

type ColumnOrder[T ~int32] interface {
	GetColumn() T
	GetOrder() proto.Order
}

func GetOrder[I ~int32, V ColumnOrder[I]](orders []V, defaultOrder string) (sqlh.Expr, error) {
	if len(orders) == 0 {
		return SQL(defaultOrder), nil
	}
	clauses := make([]string, 0, len(orders))
	for _, columnOrder := range orders {
		columnIndex := columnOrder.GetColumn()
		if columnIndex == 0 {
			return SQL(defaultOrder), errors.New("invalid column order")
		}
		order := "ASC"
		if columnOrder.GetOrder() == proto.Order_ORDER_DESC {
			order = "DESC"
		}
		clauses = append(clauses, fmt.Sprintf("%d %s", columnIndex, order))
	}
	return SQL(strings.Join(clauses, ", ")), nil
}
