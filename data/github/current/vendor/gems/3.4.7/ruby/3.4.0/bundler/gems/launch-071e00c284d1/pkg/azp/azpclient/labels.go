package azpclient

import (
	"context"
	"net/http"

	errs "github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type LabelsService struct {
	client *Client
	http   *httpclient.Client
}

type listLabelsResponse struct {
	Count int64        `json:"count"`
	Value []*azp.Label `json:"value"`
}

func (l *LabelsService) ListLabels(ctx context.Context) ([]*azp.Label, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "labels.list"

	var resp *listLabelsResponse
	err := l.http.Do(
		ctx,
		opname,
		http.MethodGet,
		l.client.url.getLabelsURL(),
		nil,
		&resp,
		l.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (l *LabelsService) DeleteLabel(ctx context.Context, id int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "labels.delete"

	validator := func(r *http.Response) (bool, error) {
		_, err := azp.ResponseValidator()(r)
		if err == nil && r.StatusCode == http.StatusNoContent {
			return false, nil
		}

		// err could still be nil here for 200s that aren't 204
		if err != nil {
			err = errs.Wrapf(err, "label delete returned %d status code, expected 204", r.StatusCode)
		}

		return r.StatusCode >= 500, err
	}

	err := l.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		l.client.url.getDeleteLabelURL(id),
		nil,
		nil,
		l.client.withDefaultOpts(ctx,
			httpclient.WithValidator(validator),
		)...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (l *LabelsService) CreateLabel(ctx context.Context, fields azp.LabelFields) (*azp.Label, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "labels.create"

	validator := func(res *http.Response) (bool, error) {
		if res.StatusCode != http.StatusCreated && res.StatusCode != http.StatusOK {
			retryable := res.StatusCode >= 500
			return retryable, errs.Errorf("label create returned %d status code, expected 201 or 200", res.StatusCode)
		}
		return azp.ResponseValidator()(res)
	}

	var resp *azp.Label
	err := l.http.Do(
		ctx,
		opname,
		http.MethodPost,
		l.client.url.getLabelsURL(),
		fields,
		&resp,
		l.client.withDefaultOpts(ctx,
			httpclient.WithValidator(validator),
			httpclient.WithRequestOptions(launchhttp.WithJSONContentType()),
		)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}
