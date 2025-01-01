package dag

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

var (
	// Test nodes
	testNode1 = Node{ID: "node1", Kind: ResourceNode}
	testNode2 = Node{ID: "node2", Kind: ResourceNode}
	testNode3 = Node{ID: "node3", Kind: ResourceNode}
)

func Test_MemoryDAG_AddNode(t *testing.T) {
	// Case: Add a node with no dependencies.
	//
	// In addition to checking that the node is added to the DAG, we
	// also need to check that the node is marked as eligible.
	dag := NewMemoryDAG()
	require.NoError(t, dag.AddNode(context.Background(), "", testNode1.Kind, testNode1.ID))
	require.Equal(t, 0, len(dag.nodeIDsToDependencies[testNode1.ID]))
	require.Equal(t, 0, len(dag.nodeIDsToDependents[testNode1.ID]))
	require.Equal(t, 1, len(dag.nodeIDsToNodes))
	require.Equal(t, 1, len(dag.eligibleNodes))
	require.Contains(t, dag.eligibleNodes, testNode1)

	// Case: Add a node with dependencies.
	//
	// `testNode1` depends on `testNode2`. `testNode2` is intentionally not added to the DAG.
	dag = NewMemoryDAG()
	require.NoError(t, dag.AddNode(context.Background(), "", testNode1.Kind, testNode1.ID, testNode2))
	require.Equal(t, 1, len(dag.nodeIDsToDependencies))
	require.Contains(t, dag.nodeIDsToDependencies, testNode1.ID)
	require.Equal(t, 1, len(dag.nodeIDsToDependencies[testNode1.ID]))
	require.Contains(t, dag.nodeIDsToDependencies[testNode1.ID], testNode2.ID)
	require.Equal(t, 1, len(dag.nodeIDsToDependents))
	require.Contains(t, dag.nodeIDsToDependents, testNode2.ID)
	require.Equal(t, 1, len(dag.nodeIDsToDependents[testNode2.ID]))
	require.Contains(t, dag.nodeIDsToDependents[testNode2.ID], testNode1.ID)
	require.Equal(t, 0, len(dag.eligibleNodes))
}

func Test_MemoryDAG_MarkAsProcessed(t *testing.T) {
	// Stage the dag.
	// Nodes 2 and 3 depends on Node 1.
	dag := NewMemoryDAG()
	require.NoError(t, dag.AddNode(context.Background(), "", testNode1.Kind, testNode1.ID))
	require.NoError(t, dag.AddNode(context.Background(), "", testNode2.Kind, testNode2.ID, testNode1))
	require.NoError(t, dag.AddNode(context.Background(), "", testNode3.Kind, testNode3.ID, testNode1))
	require.Equal(t, 1, len(dag.eligibleNodes))
	require.Contains(t, dag.eligibleNodes, testNode1)

	// Mark Node 1 as processed, require expectations.
	require.NoError(t, dag.MarkAsProcessed(context.Background(), "", []Node{testNode1}))
	require.Equal(t, struct{}{}, dag.processedNodes[testNode1.ID])
	require.NotContains(t, dag.eligibleNodes, testNode1)
	require.Equal(t, 0, len(dag.nodeIDsToDependencies[testNode2.ID]))
	require.Equal(t, 0, len(dag.nodeIDsToDependencies[testNode3.ID]))
	require.Equal(t, 2, len(dag.eligibleNodes))
	require.Contains(t, dag.eligibleNodes, testNode2)
	require.Contains(t, dag.eligibleNodes, testNode3)
}
