//go:build integrationtest

package dag

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/integration"
	"github.com/go-redis/redis/v8"
	"github.com/stretchr/testify/require"
)

func Test_RedisDAG(t *testing.T) {
	logger := log.WithLevel(log.InfoLevel)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// connect to redis
	// Set up the Redis options
	opts := &redis.Options{
		Addr:     integration.DockerComposePort(t, "redis", 6379), // Redis server address
		Password: "",                                              // No password set
		DB:       0,                                               // Use default DB
	}

	// Create a new Redis client
	c := redis.NewClient(opts)

	// Create a new RedisDAG
	ns := integration.RandomString(5)
	rDAG, err := NewRedisDAG(c, logger)
	require.NoError(t, err)

	// This is our DAG A->(B, C)->D
	nodeA := Node{ID: ID("A"), Kind: ResourceNode}
	nodeB := Node{ID: ID("B"), Kind: ResourceNode}
	nodeC := Node{ID: ID("C"), Kind: ResourceNode}
	nodeD := Node{ID: ID("D"), Kind: ResourceNode}

	// We insert the nodes in reverse order to test the ordering
	// of the eligible nodes

	// Add node D
	err = rDAG.AddNode(ctx, ns, ResourceNode, nodeD.ID, nodeB, nodeC)
	require.NoError(t, err)

	// Add node C
	err = rDAG.AddNode(ctx, ns, ResourceNode, nodeC.ID, nodeA)
	require.NoError(t, err)

	// Add node B
	err = rDAG.AddNode(ctx, ns, ResourceNode, nodeB.ID, nodeA)
	require.NoError(t, err)

	// Check there are no eligible nodes
	// as we haven't added node A yet
	eligible, err := rDAG.EligibleNodes(ctx, ns)
	require.NoError(t, err)
	require.Empty(t, eligible)

	// Add node A
	err = rDAG.AddNode(ctx, ns, ResourceNode, nodeA.ID)
	require.NoError(t, err)

	// Check that A is eligible
	eligible, err = rDAG.EligibleNodes(ctx, ns)
	require.NoError(t, err)
	require.Equal(t, nodeA, eligible[0])

	// Process A
	err = rDAG.MarkAsProcessed(ctx, ns, []Node{nodeA})
	require.NoError(t, err)

	// Check that B and C are eligible
	eligible, err = rDAG.EligibleNodes(ctx, ns)
	require.NoError(t, err)
	require.Contains(t, eligible, nodeB)
	require.Contains(t, eligible, nodeC)

	// Process B and C
	err = rDAG.MarkAsProcessed(ctx, ns, []Node{nodeB, nodeC})
	require.NoError(t, err)

	// Check that D is eligible
	eligible, err = rDAG.EligibleNodes(ctx, ns)
	require.NoError(t, err)
	require.Equal(t, nodeD, eligible[0])

	// Process D
	err = rDAG.MarkAsProcessed(ctx, ns, []Node{nodeD})
	require.NoError(t, err)

	// Check that there are no more eligible nodes
	eligible, err = rDAG.EligibleNodes(ctx, ns)
	require.NoError(t, err)
	require.Empty(t, eligible)
}
