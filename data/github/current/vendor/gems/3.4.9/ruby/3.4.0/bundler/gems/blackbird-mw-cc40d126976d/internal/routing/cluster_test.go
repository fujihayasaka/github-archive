package routing_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_RandomHost(t *testing.T) {
	cluster := helpers.SearchClustersN(t, 10)
	routes := cluster.GetServingRoutes(context.Background(), routing.Blue)

	for i := 0; i < len(routes.ServingHosts); i++ {
		require.NotNil(t, routes.RandomHost())
	}
}

func Test_RandomHostSingle(t *testing.T) {
	cluster := helpers.SearchClustersN(t, 1)
	routes := cluster.GetServingRoutes(context.Background(), routing.Blue)

	for i := 0; i < 10; i++ {
		require.NotNil(t, routes.RandomHost())
	}
}

func Test_RandomHostNoHosts(t *testing.T) {
	cluster := helpers.SearchClustersN(t, 0)
	h := cluster.GetServingRoutes(context.Background(), routing.Blue).RandomHost()
	require.Nil(t, h)
}
