package cosmos

import (
	"context"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/licensify/testing/mocks"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type testObject struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func TestExecuteQuery(t *testing.T) {
	mockDB := &mocks.MockDBReadWriter{}

	jsonDocsReturned := [][]byte{[]byte(`{"id":"1","name":"test"}`)}
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: jsonDocsReturned}, nil
		},
	})

	mockDB.On(
		"NewQueryItemsPager",
		"SELECT * From C",
		azcosmos.NewPartitionKeyString("testPk"),
		(*azcosmos.QueryOptions)(nil),
	).Return(pager).Once()

	querier := NewQuerier[*testObject](mockDB)
	items, err := querier.ExecuteQuery(context.Background(), "SELECT * From C", "testPk", nil)

	require.NoError(t, err)
	assert.Len(t, items, 1)
	assert.Equal(t, "1", items[0].ID)
	assert.Equal(t, "test", items[0].Name)
}
