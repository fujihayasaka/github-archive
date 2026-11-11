package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db/noop"
)

func Test_TimeoutDuringRetriesDoesNotNPE(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel() // cancel the context immediately to simulate a timeout

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(500)
	}))
	defer server.Close()

	authClient := NewBlackbirdInternalAPIClient(http.DefaultClient, server.URL, "blah")

	client := NewClient(cache.NewInMemory(), authClient, noop.New())
	resources, statusCode, err := client.authorizationClient.GetAccessibleResources(ctx, requestForActor(123))

	require.Nil(t, resources)
	require.Equal(t, 0, statusCode)
	require.Error(t, err)
}

func Test_GetAccessibleResourcesSuccess(t *testing.T) {
	resources := &entities.AccessibleResources{
		AccessiblePrivateRepoIds:  []uint64{1},
		AccessibleOwnerIds:        []uint64{2},
		AuthorizedOrganizationIds: []uint64{3},
		ProtectedOrganizationIds:  []uint64{4},
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data, err := json.Marshal(resources)
		// shouldn't happen
		if err != nil {
			w.WriteHeader(500)
			return
		}
		w.WriteHeader(200)
		_, err = w.Write(data)
		if err != nil {
			panic(fmt.Sprintf("really shouldn't happen: %s", err))
		}
	}))
	defer server.Close()

	authClient := NewBlackbirdInternalAPIClient(http.DefaultClient, server.URL, "blah")

	client := NewClient(cache.NewInMemory(), authClient, noop.New())
	returnedResources, statusCode, err := client.authorizationClient.GetAccessibleResources(context.Background(), requestForActor(123))
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, statusCode)
	require.Equal(t, []uint64{1}, returnedResources.AccessiblePrivateRepoIds)
	require.Equal(t, []uint64{2}, returnedResources.AccessibleOwnerIds)
	require.Equal(t, []uint64{3}, returnedResources.AuthorizedOrganizationIds)
	require.Equal(t, []uint64{4}, returnedResources.ProtectedOrganizationIds)
}
