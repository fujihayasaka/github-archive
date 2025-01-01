package engines

import (
	"context"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

type MockInvoiceQuerier struct {
	queryItems            func(ctx context.Context, logger log.Logger, query string, partitionKey string) ([]*models.Invoice, error)
	queryItemsWithOptions func(ctx context.Context, logger log.Logger, query string, partitionKey string, retryCount int, options *azcosmos.QueryOptions) ([]*models.Invoice, error)
	queryItemsAsyncBatch  func(ctx context.Context, logger log.Logger, query string, partitionKey string) (<-chan []*models.Invoice, <-chan error)
	readItemWithRetries   func(ctx context.Context, logger log.Logger, key models.ItemKey) (*models.Invoice, error)
}

func (m *MockInvoiceQuerier) QueryItems(ctx context.Context, logger log.Logger, query string, partitionKey string) ([]*models.Invoice, error) {
	return m.queryItems(ctx, logger, query, partitionKey)
}

func (m *MockInvoiceQuerier) QueryItemsWithOptions(ctx context.Context, logger log.Logger, query string, partitionKey string, retryCount int, options *azcosmos.QueryOptions) ([]*models.Invoice, error) {
	return m.queryItemsWithOptions(ctx, logger, query, partitionKey, retryCount, options)
}

func (m *MockInvoiceQuerier) QueryItemsAsyncBatch(ctx context.Context, logger log.Logger, query string, partitionKey string) (<-chan []*models.Invoice, <-chan error) {
	return m.queryItemsAsyncBatch(ctx, logger, query, partitionKey)
}

func (m *MockInvoiceQuerier) ReadItemWithRetries(ctx context.Context, logger log.Logger, key models.ItemKey) (*models.Invoice, error) {
	return m.readItemWithRetries(ctx, logger, key)
}

func TestGetInvoices(t *testing.T) {
	t.Parallel()
	customerID := "1"
	year := int64(2019)
	month := int64(3)

	params := &EngineParams{}

	testInvoices := []*models.Invoice{
		models.NewInvoice(&models.InvoicePartitionDetail{
			CustomerId: customerID,
			Period:     models.InvoiceMonthly,
			Year:       year,
			Month:      month,
		}, nil, nil),
		models.NewInvoice(&models.InvoicePartitionDetail{
			CustomerId: customerID,
			Period:     models.InvoiceMonthly,
			Year:       year,
			Month:      month,
		}, nil, nil),
	}
	engine := NewInvoiceEngine(params)
	engine.invoiceQuerier = func() db.ModelQuerier[*models.Invoice] {
		return &MockInvoiceQuerier{
			queryItems: func(ctx context.Context, logger log.Logger, query string, partitionKey string) ([]*models.Invoice, error) {
				if query != db.QueryStringAll {
					t.Errorf("Expected query string to be %s, got %s", db.QueryStringAll, query)
				}

				// return error if partitionKey includes error
				if partitionKey == models.CustomerIdToInvoicePartitionKey("error") {
					return nil, errors.New("database error")
				}

				return testInvoices, nil
			},
		}
	}

	t.Run("GetInvoices with valid customerID", func(t *testing.T) {
		t.Parallel()
		invoices, err := engine.GetInvoices(context.Background(), nil, customerID)
		if err != nil {
			t.Errorf("Unexpected error: %v", err)
		}

		if len(invoices) != len(testInvoices) {
			t.Errorf("Expected %d invoices, got %d", len(testInvoices), len(invoices))
		}

		for i, invoice := range invoices {
			if invoice != testInvoices[i] {
				t.Errorf("Expected invoice %d to be %v, got %v", i, testInvoices[i], invoice)
			}
		}
	})

	t.Run("GetInvoices returns an error returned by the querier", func(t *testing.T) {
		t.Parallel()
		_, err := engine.GetInvoices(context.Background(), nil, "error")
		if err == nil {
			t.Errorf("Expected error, got nil")
		}
	})
}
