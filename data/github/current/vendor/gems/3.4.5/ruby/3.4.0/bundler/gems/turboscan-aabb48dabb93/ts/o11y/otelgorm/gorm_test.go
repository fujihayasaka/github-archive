package otelgorm_test

import (
	"bytes"
	"context"
	"io"
	"testing"

	ghtrace "github.com/github/github-telemetry-go/trace"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/jinzhu/gorm"
	_ "github.com/jinzhu/gorm/dialects/sqlite"
	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/otel"
)

func TestOtelGorm(t *testing.T) {
	// Initialize GORM
	db, err := gorm.Open("sqlite3", "file::memory:?cache=shared")
	require.NoError(t, err)
	defer db.Close()

	// Setup the tracer and instrument GORM
	out, stop := setupTracer(t)
	otelgorm.Initialize(db)

	// Run the example function
	err = exampleFunc(context.Background(), db)
	require.NoError(t, err)

	// Stop the tracing and check the output
	require.NoError(t, stop(context.Background()))
	outStr := out.String()
	require.NotEmpty(t, outStr)

	expectedLines := []string{
		// Create
		`"Name": "gorm.Create"`,
		`"Value": "INSERT INTO \"products\" (\"code\",\"price\") VALUES (?,?)"`,
		// Query
		`"Name": "gorm.Query"`,
		`"Value": "SELECT * FROM \"products\"  WHERE (\"products\".\"id\" = 1) ORDER BY \"products\".\"id\" ASC LIMIT 1"`,
		// Update
		`"Name": "gorm.Update"`,
		`"Value": "UPDATE \"products\" SET \"price\" = ?  WHERE \"products\".\"id\" = ?"`,
		// Delete
		`"Name": "gorm.Delete"`,
		`"Value": "DELETE FROM \"products\"  WHERE \"products\".\"id\" = ?"`,
		// Row
		`"Name": "gorm.Row"`,
		`"Value": "SELECT * FROM \"products\"  WHERE \"products\".\"id\" = ? AND ((code = ?))"`,
	}
	for idx, expected := range expectedLines {
		require.Contains(t, outStr, expected, "line %d", idx)
	}
}

func setupTracer(t *testing.T) (*bytes.Buffer, func(context.Context) error) {
	t.Helper()

	out := new(bytes.Buffer)
	tracer, err := ghtrace.NewFromEnv(
		ghtrace.WithExporterWriter(io.Writer(out)),
		// !!! The exporter must be set to ExporterStdout to get the trace into the buffer !!!
		ghtrace.WithExporter(ghtrace.ExporterStdout),
	)
	require.NoError(t, err)

	// Set the global tracer provider.
	otel.SetTracerProvider(tracer.Provider)
	return out, tracer.Provider.Shutdown
}

// exampleFunc is a simple function showing how to use GORM with OpenTelemetry.
// We do one query per operation that we instrumented.
func exampleFunc(ctx context.Context, db *gorm.DB) error {
	// Instrument the GORM instance
	db = otelgorm.SetSpanToGorm(ctx, db)

	// Create a table and add some data
	err := db.AutoMigrate(&Product{}).Error
	if err != nil {
		return err
	}

	// Create
	err = db.Create(&Product{Code: "L1212", Price: 1000}).Error
	if err != nil {
		return err
	}

	// Read
	var product Product
	err = db.First(&product, 1).Error
	if err != nil {
		return err
	}

	// Update - update product's price to 2000
	err = db.Model(&product).Update("Price", 2000).Error
	if err != nil {
		return err
	}

	// Rows
	err = db.Model(&product).Where("code = ?", "L1212").Row().Scan(&product.ID, &product.Code, &product.Price)
	if err != nil {
		return err
	}

	// Delete - delete product
	err = db.Delete(&product).Error
	if err != nil {
		return err
	}

	return nil
}

type Product struct {
	ID    uint64
	Code  string
	Price uint
}
