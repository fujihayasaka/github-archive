// Package gormbulk provides a bulk insert library which uses Freno to throttle writes.
package gormbulk

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"reflect"
	"strings"
	"sync/atomic"
	"time"

	throttler "github.com/github/go-freno-client"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
	"golang.org/x/exp/slices"
)

// InsertOptions is used to configure the bulk Insert function
type InsertOptions[T any] struct {
	// DB is the database connection used to make the bulk operations
	DB *gorm.DB

	// Objects are the records to be inserted. Must be a slice of struct pointers.
	Objects []*T

	// ChunkSize is the number of records to insert at once. Embedding a large
	// number of variables at once will raise an error beyond the limit of
	// prepared statement.  Larger size will normally lead the better
	// performance, but 2000 to 3000 is reasonable.
	ChunkSize int
}

// scanPrimaryKeys reloads the ID fields for any objects passed in.
// It uses the condition function to find existing records.
func scanPrimaryKeys[T any](ctx context.Context, db *gorm.DB, condition func(*gorm.DB, *T) *gorm.DB, objects []*T, found map[uint64]struct{}) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db = otelgorm.SetSpanToGorm(ctx, db)

	subqueries := make([]*gorm.SqlExpr, 0, len(objects))

	// build a list of subqueries, one for each row that needs an ID
	// select the index in the slice so that we can update it in the next step
	for idx, object := range objects {
		scope := db.NewScope(object)
		primaryField := scope.PrimaryField()
		if primaryField == nil {
			return errors.New("cannot insert ignore without a primary field")
		}

		subquery := condition(db.Table(scope.TableName()), object)
		if subquery == nil {
			return errors.New("insert ignore condition returned nil")
		}
		if subquery.Error != nil {
			return errors.Wrap(subquery.Error, "failed to create primary key condition during insert ignore")
		}

		cols := fmt.Sprintf("? AS 'index', %s AS 'id'", scope.Quote(primaryField.DBName))
		subqueries = append(subqueries, subquery.Select(cols, idx).SubQuery())
	}

	// nothing to do
	if len(subqueries) == 0 {
		return nil
	}

	var rows []struct {
		Index int
		ID    uint64
	}
	// Execute the query as a UNION of all the subqueries.
	// This trades a nasty UNION query that is hard to canonicalize for much simpler application code.
	// If we wanted to use an IN clause it would require much more mapping between data.
	err := gormext.Union(db, subqueries...).Scan(&rows).Error
	if err != nil {
		return errors.Wrap(err, "error running union query")
	}

	// each row returned contains a slice index and a primary key
	// iterate through, updating the structs in-place.
	for _, row := range rows {
		o := objects[row.Index]
		scope := db.NewScope(o)
		primaryField := scope.PrimaryField()
		if primaryField == nil {
			return errors.New("cannot insert ignore without a primary field")
		}
		err := primaryField.Set(row.ID)
		if err != nil {
			return errors.Wrap(err, "failed to update primary key")
		}
		found[row.ID] = struct{}{}
	}

	return nil
}

func hasKey[K comparable, V any](items map[K]V, key K) bool {
	_, ok := items[key]
	return ok
}

// selectNew filters out any records that already have a PrimaryField that is not blank
func selectNew[T any](db *gorm.DB, objects []*T, seen map[uint64]struct{}) ([]*T, error) {
	out := make([]*T, 0, len(objects))
	for _, o := range objects {
		primaryField := db.NewScope(o).PrimaryField()
		if primaryField == nil {
			return nil, errors.New("cannot insert ignore without a primary field")
		}
		if primaryField.IsBlank || !hasKey(seen, primaryField.Field.Uint()) {
			out = append(out, o)
		}
	}
	return out, nil
}

// execBeforeCreate runs the beforeCreate callback for all the objects.
func execBeforeCreate[T any](ctx context.Context, db *gorm.DB, objects []*T) error {
	_, span := o11y.StartSpan(ctx)
	defer span.End()
	// run gorm:before_create before determining the insert columns as before_create can alter them
	// by adding additional columns
	for _, obj := range objects {
		scope := db.NewScope(obj)
		f := db.Callback().Create().Get(beforeCreate)
		if f == nil {
			return errors.New("No callback registered under the name '" + beforeCreate + "'")
		}
		f(scope)
		if scope.HasError() {
			return scope.DB().Error
		}
	}
	return nil
}

// InsertIgnore insert ignores multiple records at once for the given Objects in the
// options. It will call condition on each record to load the primary key before and after the insert.
//
// NOTE: This method has been modified from the original and must be used
// carefully:
//
// 1. It is only safe to use on MySQL outside a transaction.
//
// 2. You must pass a slice of pointers, as this way the elements of
// the original typed slice will be updated and you won't have to copy
// them back from the untyped slice.
//
// 3. Do NOT assume that any GORM callbacks apart from `BeforeSave`
// are called. Associations are also not written by this function.
//
// 4. The returned records do not have new values of CreatedAt and
// UpdatedAt.
func InsertIgnore[T any](ctx context.Context, condition func(*gorm.DB, *T) *gorm.DB, opt *InsertOptions[T]) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, opt.DB).Set("gorm:insert_modifier", "IGNORE")

	if len(opt.Objects) == 0 {
		return nil
	}

	// keep track of the things we have found ids for
	found := make(map[uint64]struct{}, len(opt.Objects))

	// Step one, attempt to find all the existing records from the database.
	err := execInChunks(ctx, opt.Objects, opt.ChunkSize, func(chunk []*T) error {
		// First run the before create hooks.
		// Some records will update fields that are used in the unique key query, and
		// we want those values to be correct before we load the IDs.
		if err := execBeforeCreate(ctx, db, chunk); err != nil {
			return err
		}

		// attempt to load any records that already exist in the database using their unique keys
		// we can skip inserting them to reduce the chance of deadlocking when doing an INSERT IGNORE
		return errors.Wrap(scanPrimaryKeys(ctx, db, condition, chunk, found), "error scanning primary keys")
	})
	if err != nil {
		return err
	}

	// Select any objects that may not exist in the database.
	newObjects, err := selectNew(db, opt.Objects, found)
	if err != nil {
		return err
	}

	tableName := db.NewScope(opt.Objects[0]).TableName()

	appctx.Stats(ctx).Counter("gormbulk.insert_ignore", stats.Tags{"type": "hit", "table": tableName}, int64(len(opt.Objects)-len(newObjects)))
	appctx.Stats(ctx).Counter("gormbulk.insert_ignore", stats.Tags{"type": "miss", "table": tableName}, int64(len(newObjects)))

	// Step two insert all the remaining (new) records into the database and fetch their IDs.
	// Use chunks of records with specified size so as not to exceed Database parameter limit.
	err = execInChunks(ctx, newObjects, opt.ChunkSize, func(chunk []*T) error {
		// make sure we're waiting for the throttler at most 5 seconds (freno
		// is fast)  and return an error if we're still not allowed. We should
		// tweak this timeout based on our replication lag and how long we're
		// getting throttled.
		ctx, cancel := context.WithTimeout(ctx, time.Second*5)
		defer cancel()

		err := waitOnThrottler(ctx)
		if err != nil {
			return err
		}

		if _, err = insertObjSet(ctx, db, chunk); err != nil {
			return err
		}

		// load any remaining ids before returning to the caller.
		return scanPrimaryKeys(ctx, db, condition, chunk, found)
	})
	if err != nil {
		return err
	}

	// check that we have managed to find every primary key
	// this verifies that the insert ignore condition is working correctly
	for _, object := range newObjects {
		scope := db.NewScope(object)
		primaryField := scope.PrimaryField()
		if primaryField == nil {
			return errors.New("cannot insert ignore without a primary field")
		}
		if primaryField.IsBlank {
			return errors.Errorf("failed to load primary key for %T", object)
		}
	}

	return nil
}

var GetAutoIncrementIncrement = func() func(db *gorm.DB) (int64, error) {
	var value atomic.Int64
	return func(db *gorm.DB) (int64, error) {
		var autoIncrementIncrement int64
		if autoIncrementIncrement = value.Load(); autoIncrementIncrement > 0 {
			return autoIncrementIncrement, nil
		}
		err := db.CommonDB().QueryRow("SELECT @@SESSION.auto_increment_increment").Scan(&autoIncrementIncrement)
		if err == nil && autoIncrementIncrement == 0 {
			err = errors.New("auto_increment_increment cannot be zero")
		}
		if err != nil {
			value.Store(autoIncrementIncrement)
		}
		return autoIncrementIncrement, err
	}
}()

// Insert inserts multiple records at once for the given Objects in the
// options.
//
// NOTE: This method has been modified from the original and must be used
// carefully:
//
// 1. It is only safe to use on MySQL outside a transaction.
//
// 2. You must pass a slice of pointers, as this way the elements of
// the original typed slice will be updated and you won't have to copy
// them back from the untyped slice.
//
// 3. Do NOT assume that any GORM callbacks apart from `BeforeSave`
// are called. Associations are also not written by this function.
//
// 4. The returned records do not have new values of CreatedAt and
// UpdatedAt.
func Insert[T any](ctx context.Context, opt *InsertOptions[T]) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, opt.DB)

	autoIncrementIncrement, err := GetAutoIncrementIncrement(db)
	if err != nil {
		return errors.Wrap(err, "failed to load auto increment increment")
	}

	if err := execInChunks(ctx, opt.Objects, opt.ChunkSize, func(chunk []*T) error {
		return execBeforeCreate(ctx, db, chunk)
	}); err != nil {
		return err
	}

	// Use chunks of records with specified size so as not to exceed Database parameter limit
	return execInChunks(ctx, opt.Objects, opt.ChunkSize, func(chunk []*T) error {
		// make sure we're waiting for the throttler at most 5 seconds (freno
		// is fast)  and return an error if we're still not allowed. We should
		// tweak this timeout based on our replication lag and how long we're
		// getting throttled.
		ctx, cancel := context.WithTimeout(ctx, time.Second*5)
		defer cancel()

		err := waitOnThrottler(ctx)
		if err != nil {
			return err
		}

		result, err := insertObjSet(ctx, db, chunk)
		if err != nil {
			return err
		}

		firstId, err := result.LastInsertId()
		if err != nil {
			return err
		}

		return setIDs(db, firstId, chunk, autoIncrementIncrement)
	})
}

func setIDs[T any, S ~[]T](db *gorm.DB, firstId int64, items S, increment int64) error {
	for j, o := range items {
		scope := db.NewScope(o)
		primaryField := scope.PrimaryField()
		if primaryField != nil && primaryField.IsBlank {
			// Update the ID field using an offset from the first ID used
			err := primaryField.Set(firstId + (int64(j) * increment))
			if err != nil {
				return err
			}
		}
	}
	return nil
}

// This name must match that used in GORM's default callback
// initialization (currently at
// https://github.com/jinzhu/gorm/blob/7ea143b5484fe28148d5c73cfd43b26e8a89c94e/callback_create.go#L11).
const beforeCreate = "gorm:before_create"

func addExtraSpaceIfExist(str string) string {
	if str != "" {
		return " " + str
	}
	return ""
}

func insertObjSet[T any](ctx context.Context, db *gorm.DB, objects []*T) (sql.Result, error) {
	_, span := o11y.StartSpan(ctx)
	defer span.End()

	if len(objects) == 0 {
		return nil, nil
	}

	firstAttrs, err := extractMapValue(db, objects[0])
	if err != nil {
		return nil, err
	}

	attrSize := len(firstAttrs)

	// Scope to eventually run SQL
	mainScope := db.NewScope(objects[0])
	// Store placeholders for embedding variables
	placeholders := make([]string, 0, attrSize)

	// Replace with database column name
	dbColumns := make([]string, 0, attrSize)
	for _, key := range sortedKeys(firstAttrs) {
		dbColumns = append(dbColumns, mainScope.Quote(gorm.ToColumnName(key)))
	}

	for _, obj := range objects {
		scope := db.NewScope(obj)

		objAttrs, err := extractMapValue(db, obj)
		if err != nil {
			return nil, err
		}

		// If object sizes are different, SQL statement loses consistency
		if len(objAttrs) != attrSize {
			return nil, errors.New("attribute sizes are inconsistent")
		}

		// Append variables
		variables := make([]string, 0, attrSize)
		for _, key := range sortedKeys(objAttrs) {
			scope.AddToVars(objAttrs[key])
			variables = append(variables, "?")
		}

		valueQuery := "(" + strings.Join(variables, ", ") + ")"
		placeholders = append(placeholders, valueQuery)

		// Also append variables to mainScope
		mainScope.SQLVars = append(mainScope.SQLVars, scope.SQLVars...)
	}

	var insertModifier, insertOption string

	if val, ok := db.Get("gorm:insert_option"); ok {
		strVal, ok := val.(string)
		if !ok {
			return nil, errors.New("gorm:insert_option should be a string")
		}
		insertOption = strVal
	}

	if str, ok := db.Get("gorm:insert_modifier"); ok {
		insertModifier = strings.ToUpper(fmt.Sprint(str))
		if insertModifier == "INTO" {
			insertModifier = ""
		}
	}

	mainScope.Raw(fmt.Sprintf("INSERT%v INTO %s (%s) VALUES %s%v",
		addExtraSpaceIfExist(insertModifier),
		mainScope.QuotedTableName(),
		strings.Join(dbColumns, ", "),
		strings.Join(placeholders, ", "),
		addExtraSpaceIfExist(insertOption),
	))

	return db.CommonDB().Exec(mainScope.SQL, mainScope.SQLVars...)
}

// Obtain columns and values required for insert from interface
func extractMapValue(db *gorm.DB, value interface{}) (map[string]interface{}, error) {
	rv := reflect.ValueOf(value)
	if rv.Kind() == reflect.Ptr {
		rv = rv.Elem()
		value = rv.Interface()
	}
	if rv.Kind() != reflect.Struct {
		return nil, errors.New("value must be kind of Struct")
	}

	var attrs = map[string]interface{}{}

	// Get the time now so that updated and created at is set at the same time
	now := time.Now()

	scope := db.NewScope(value)
	omit := scope.OmitAttrs()

	for _, field := range scope.Fields() {
		// Exclude relational record because it's not directly contained in database columns
		_, hasForeignKey := field.TagSettingsGet("FOREIGNKEY")

		if field.StructField.Relationship == nil && !hasForeignKey &&
			!field.IsIgnored && !fieldIsAutoIncrement(field) && !fieldIsPrimaryAndBlank(field) {

			switch {
			case slices.Contains(omit, field.Name):
				if val := field.Struct.Tag.Get("gormbulk"); val == "omitzero" {
					attrs[field.DBName] = reflect.Zero(field.Field.Type()).Interface()
				}
				continue
			case (field.Struct.Name == "CreatedAt" || field.Struct.Name == "UpdatedAt") && field.IsBlank:
				attrs[field.DBName] = now
			case field.StructField.HasDefaultValue && field.IsBlank:
				// If default value presents and field is empty, assign a default value
				if val, ok := field.TagSettingsGet("DEFAULT"); ok {
					attrs[field.DBName] = val
				} else {
					attrs[field.DBName] = field.Field.Interface()
				}
			default:
				attrs[field.DBName] = field.Field.Interface()
			}
		}
	}
	return attrs, nil
}

func fieldIsAutoIncrement(field *gorm.Field) bool {
	if value, ok := field.TagSettingsGet("AUTO_INCREMENT"); ok {
		return strings.ToLower(value) != "false"
	}
	return false
}

func fieldIsPrimaryAndBlank(field *gorm.Field) bool {
	return field.IsPrimaryKey && field.IsBlank
}

// waitOnThrottler waits exponentially until the given throttler allows us to
// write or the context is canceled (typical use would be to pass a context with
// a timeout or deadline). The wait time between requests to the throttler is
// capped at 1s as that's how long the app sleeps. It returns an error if
// writing should not be done.
func waitOnThrottler(ctx context.Context) error {
	st := time.Now()

	for tries := 0; ; tries++ {
		can, err := appctx.Throttler(ctx).CanWrite(ctx)
		if can {
			return nil
		}

		appctx.Stats(ctx).Counter("freno.throttled", stats.Tags{"component": "mysql"}, 1)

		sleepTime := time.Duration(math.Exp2(float64(tries))) * 20 * time.Millisecond
		if sleepTime > 1*time.Second {
			sleepTime = 1 * time.Second
		}

		select {
		case <-ctx.Done():
			if err != nil {
				return errors.Wrap(err, "error waiting on the throttler")
			}
			return errors.Wrap(&throttler.ErrTimeout{Duration: time.Since(st).Truncate(time.Second)}, "throttler wait timeout")
		case <-time.After(sleepTime):
			continue
		}
	}
}
