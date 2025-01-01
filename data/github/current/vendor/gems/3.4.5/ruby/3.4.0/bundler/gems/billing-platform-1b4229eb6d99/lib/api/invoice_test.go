package api

import (
	"context"
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

type invoiceEngineMock struct {
	invoices []*models.Invoice
}

func (i *invoiceEngineMock) GetInvoices(ctx context.Context, logger log.Logger, customerID string) ([]*models.Invoice, error) {
	if customerID == "error" {
		return nil, errors.New("error fetching invoices")
	} else if customerID == "no-invoices" {
		return []*models.Invoice{}, nil
	}

	return i.invoices, nil
}

func TestGetInvoices(t *testing.T) {
	t.Parallel()
	customerID := "1"
	year := int64(2019)
	month := int64(3)
	engineMock := &invoiceEngineMock{[]*models.Invoice{
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
	}}
	invoiceAPI := NewInvoiceAPI(engineMock, log.NewNullLogger())

	t.Run("returns an error when customer id is empty", func(t *testing.T) {
		t.Parallel()
		req := &proto.GetInvoicesRequest{}
		_, err := invoiceAPI.GetInvoices(context.Background(), req)
		if err == nil {
			t.Errorf("expected error but got none")
		}

		twerr, ok := err.(twirp.Error)
		if !ok {
			t.Errorf("expected a twirp error but got %v", err)
		}

		if twerr.Code() != twirp.InvalidArgument {
			t.Errorf("expected an invalid argument error but got %v", twerr.Code())
		}

		if twerr.Msg() != "customer_id is required" {
			t.Errorf("expected an invalid argument error but got %v", twerr.Msg())
		}
	})

	t.Run("returns en error when invoice engine returns an error", func(t *testing.T) {
		t.Parallel()
		req := &proto.GetInvoicesRequest{CustomerId: "error"}
		_, err := invoiceAPI.GetInvoices(context.Background(), req)
		if err == nil {
			t.Errorf("expected error but got none")
		}
		twerr, ok := err.(twirp.Error)
		if !ok {
			t.Errorf("expected a twirp error but got %v", err)
		}

		if twerr.Code() != twirp.Internal {
			t.Errorf("expected an Internal error but got %v", twerr.Code())
		}

		if twerr.Msg() != "error fetching invoices" {
			t.Errorf("expected an invalid argument error but got %v", twerr.Msg())
		}
	})

	t.Run("returns an empty list when invoice engine returns no invoices", func(t *testing.T) {
		t.Parallel()
		req := &proto.GetInvoicesRequest{CustomerId: "no-invoices"}
		resp, err := invoiceAPI.GetInvoices(context.Background(), req)
		if err != nil {
			t.Errorf("expected no error but got %v", err)
		}
		if len(resp.Invoices) != 0 {
			t.Errorf("expected no invoices but got %v", resp.Invoices)
		}
	})

	t.Run("a list of invoices when the invoice engine returns invoices", func(t *testing.T) {
		t.Parallel()
		req := &proto.GetInvoicesRequest{CustomerId: customerID}
		resp, err := invoiceAPI.GetInvoices(context.Background(), req)
		if err != nil {
			t.Errorf("expected no error but got %v", err)
		}
		if len(resp.Invoices) != 2 {
			t.Errorf("expected 2 invoices but got %v", resp.Invoices)
		}
	})
}
