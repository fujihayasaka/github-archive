package api

import (
	"context"

	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/twitchtv/twirp"
)

type InvoiceAPI struct {
	invoiceEngine engines.InvoiceLister
	logger        log.Logger
}

func NewInvoiceAPI(invoiceEngine engines.InvoiceLister, logger log.Logger) *InvoiceAPI {
	return &InvoiceAPI{
		invoiceEngine: invoiceEngine,
		logger:        logger,
	}
}

func (api *InvoiceAPI) GetInvoices(ctx context.Context, req *proto.GetInvoicesRequest) (*proto.GetInvoicesResponse, error) {
	if req.CustomerId == "" {
		return nil, twirp.RequiredArgumentError("customer_id")
	}

	invoices, err := api.invoiceEngine.GetInvoices(ctx, api.logger, req.CustomerId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	protoInvoices := make([]*proto.Invoice, len(invoices))
	for i, invoice := range invoices {
		protoInvoices[i] = invoice.ToProto()
	}

	return &proto.GetInvoicesResponse{
		Invoices: protoInvoices,
	}, nil
}
