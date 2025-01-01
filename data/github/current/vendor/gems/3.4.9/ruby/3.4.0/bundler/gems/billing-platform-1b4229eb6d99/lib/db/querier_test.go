package db

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/mocks"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
	"github.com/petergtz/pegomock/v4"
	"github.com/pkg/errors"
)

func TestQuerierItemsReturned(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	item := &models.Item{Key: models.Key{PartitionKey: "pk1", Id: "id1"}, SourceUri: "a uri"}

	marshalledItem, err := json.Marshal(item)
	g.Expect(err).To(gomega.BeNil())

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, marshalledItem)

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: itemsReturned}, nil
		},
	})

	mocker := pegomock.WithT(t)
	fakeContainer := fakes.NewMockCosmosConnection(mocker)

	querierTestObject := &Querier[models.Item]{container: fakeContainer, tracer: fakes.NewMockTracer(mocker), statter: &mocks.Statter{}}

	pegomock.When(
		querierTestObject.container.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	telem, err := telemetry.NewFromEnv()
	g.Expect(err).To(gomega.BeNil())

	logger := telem.Logger
	partitionKey := uuid.NewString()

	items, err := querierTestObject.QueryItemsWithOptions(context.TODO(), logger, "select * from c where c.id = 'id1'", partitionKey, 2, nil)
	g.Expect(err).To(gomega.BeNil())
	g.Expect(len(items)).To(gomega.Equal(1))
	g.Expect(items[0].Key.Id).To(gomega.Equal("id1"))
	fakeContainer.VerifyWasCalled(pegomock.Times(1)).NewQueryItemsPager(pegomock.Any[string](), pegomock.Any[azcosmos.PartitionKey](), pegomock.Any[*azcosmos.QueryOptions]())

}

func TestQuerierRetries429TooManyRequests(t *testing.T) {

	// make 429 Response error
	fakeURL, err := url.Parse("https://fakeurl.com/the/path?qp=removed")
	if err != nil {
		t.Fatal(err)
	}

	resp := http.Response{StatusCode: http.StatusTooManyRequests, Body: http.NoBody, Request: &http.Request{
		Method: http.MethodGet,
		URL:    fakeURL,
	}}

	handler := runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{}, errors.Wrap(runtime.NewResponseError(&resp), "an error")
		}}

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](handler)

	g := gomega.NewGomegaWithT(t)

	mocker := pegomock.WithT(t)

	fakeContainer := fakes.NewMockCosmosConnection(mocker)

	querierTestObject := &Querier[models.Item]{container: fakeContainer, tracer: fakes.NewMockTracer(mocker), statter: &mocks.Statter{}}

	pegomock.When(
		querierTestObject.container.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	telem, err := telemetry.NewFromEnv()
	g.Expect(err).To(gomega.BeNil())

	logger := telem.Logger
	partitionKey := uuid.NewString()

	items, err := querierTestObject.QueryItemsWithOptions(context.TODO(), logger, "select * from c where c.id = 'billable'", partitionKey, 2, nil)
	g.Expect(err).Should(gomega.MatchError(gomega.ContainSubstring("429")))
	g.Expect(len(items)).To(gomega.Equal(0))
	fakeContainer.VerifyWasCalled(pegomock.Times(3)).NewQueryItemsPager(pegomock.Any[string](), pegomock.Any[azcosmos.PartitionKey](), pegomock.Any[*azcosmos.QueryOptions]())

}
