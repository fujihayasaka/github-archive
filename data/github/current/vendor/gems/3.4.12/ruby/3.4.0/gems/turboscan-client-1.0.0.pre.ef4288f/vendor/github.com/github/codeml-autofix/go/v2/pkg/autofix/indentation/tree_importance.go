package indentation

import (
	"maps"
	"math"
	"slices"

	"github.com/pkg/errors"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
)

// TreeImportanceWeights is the set of weights needed to compute the importance of nodes in an indentation tree.
type TreeImportanceWeights struct {
	// Parent is the weight when going to the parent in the tree.
	Parent float64
	// Sibling is the weight when going to an immediate sibling in the tree.
	Sibling float64
	// Child is the weight when going to a child in the tree.
	Child float64
	// Switch is the penalty when direction is switched in the tree.
	// For example, when first going to a parent, and then to a sibling of that parent.
	Switch float64
}

// Get returns the weight for the given direction.
func (w TreeImportanceWeights) Get(direction TreeDirection) float64 {
	switch direction {
	case Parent:
		return w.Parent
	case Sibling:
		return w.Sibling
	case Child:
		return w.Child
	}
	panic("unknown TreeDirection")
}

// TreeDirection enumerates traversal directions in the indentation tree.
type TreeDirection int

const (
	Parent TreeDirection = iota
	Sibling
	Child
)

var treeDirectionName = map[TreeDirection]string{
	Parent:  "parent",
	Sibling: "sibling",
	Child:   "child",
}

// Multiplier returns the multiplier for the given direction.
// If the direction is the same as the current direction, the multiplier is the weight for the direction.
// Otherwise, the multiplier is the weight for the direction multiplied by the switch weight.
func (d TreeDirection) Multiplier(newDirection TreeDirection, weights TreeImportanceWeights) float64 {
	if d == newDirection {
		return weights.Get(d)
	}
	return weights.Get(d) * weights.Switch
}

// String returns the name of the direction.
func (d TreeDirection) String() string {
	return treeDirectionName[d]
}

// QueueItem is an item in the priority queue used to compute the importance of nodes in an indentation tree.
type QueueItem struct {
	// Importance is the current importance of the node. The node will have at least this importance.
	Importance float64
	// Node is the node in the tree.
	Node *IndentationTreeNode
	// Direction is the direction of the edge that gave rise to `Importance`.
	Direction TreeDirection
}

// Priority implements the QueueItem interface returning the importance used
// by the priority queue when propagating importance through the tree.
func (item QueueItem) Priority() float64 { return item.Importance }

// directionImportanceMap is a map from direction to importance.
// The default importance is negative infinity.
type directionImportanceMap map[TreeDirection]float64

func (m directionImportanceMap) Get(direction TreeDirection) float64 {
	if importance, ok := m[direction]; ok {
		return importance
	}
	return math.Inf(-1)
}

// ImportanceMap maps nodes to their importance in each direction.
// The default importance is negative infinity.
type ImportanceMap map[*IndentationTreeNode]directionImportanceMap

// Get returns the directionImportanceMap for a node creating one if needed.
func (m ImportanceMap) Get(node *IndentationTreeNode) directionImportanceMap {
	if _, ok := m[node]; !ok {
		m[node] = make(directionImportanceMap)
	}
	return m[node]
}

// DefaultTreeImportanceWeights returns the default weights for computing the importance of nodes in an indentation tree.
func DefaultTreeImportanceWeights() TreeImportanceWeights {
	return TreeImportanceWeights{
		Parent: 0.6,
		// high, because it's only the nearest siblings, not all siblings
		Sibling: 0.9,
		Child:   0.5,
		// The multiplier when "direction" is switched in the tree. E.g. when
		// first going to a parent, and then a sibling of that parent.
		Switch: 0.1,
	}
}

// ComputeImportance computes an importance for all nodes within an indentation tree based on the relations in the tree.
//
// This importance is a number between 0 and 1.
// Nodes with lower importance will be discarded first when the tree is pruned to fit within a certain budget. (See `snippetRenderer.ts`).
// An initial set of critical lines is provided, and the nodes that start/end at these lines are given the maximum importance of 1.
// Every other node is assigned an importance based on how close in the indentation-tree the node is to one of the nodes that start/end at a critical line.
//
// The algorithm does the following:
//   - Nodes that start/end at a critical line are given an importance of 1.
//   - Then edges are created to all adjacent nodes in the tree, where the importance of those nodes is calculated as the importance of the current node times a weight.
//   - The weight depends on the direction. Either it's a parent, child (only first/last child), or sibling (only the two closest adjacent siblings).
//   - If the direction changes, the weight is multiplied by a penalty factor called `switch`. E.g. traversing the tree to a "grandparent" just multiplies the parent weight twice. But transversing to a "cousin" multiplies the parent, child, and switch weight.
//   - The end importance of a node is the maximum importance of all incoming edges.
//   - The above runs until a greatest fixpoint is reached, and all nodes have a stable importance.
//
// Alternatively, the algorithm can be viewed as a graph algorithm:
// We take the indentation tree and construct a graph from it, where each node in the graph is an indentation-tree node labelled with a direction, intuitively meaning that we arrived at the node from that direction.
// Edges are added between those nodes reflecting the parent-child and sibling relations in the indentation tree; their weights are determined by the basic weights for moving between parents and children and between siblings,
// potentially multiplied by the switch weight (which is why we need to tag nodes in the graph with their direction).
// Then we do a Dijkstra "shortest-path" over the max-product semiring (i.e., empty paths have weight 1, edge weights along the same path are multiplied,
// and weights from multiple paths are combined using max), with the nodes corresponding to critical lines as our start nodes.
// Finally, we project back from the graph to the indentation tree by taking the maximum weight of all graph nodes corresponding to a tree node.
//
// As an example consider the below source code:
// ```
// 1: print "Hello"
// 2: if condition:
// 3:   print "World"
// 4:   if something:
// 5:     print " works"
// 6:   end if
// 7:   while other:
// 8:     print "!" # <- critical line. The algorithm starts from here.
// 9:   end while
// 10: end if
// ```
//
// The above gets parsed into the following indentation tree, where each node is indicated by `startline-endline`, and parent-child relationships are indicated by indentation levels:
// ```
// 1-1
// 2-10
//
//	3-3
//	4-6
//	  5-5
//	7-9
//	  8-8 # <- critical line
//
// ```
//
// There are infinitely many ways to walk from one node to another in this tree (if you include cycles).
// E.g. to go from the `8-8` node to the `3-3` node, we could walk `parent -> sibling -> sibling`, or `parent -> parent -> child`.
// Which of those will result in the highest importance depends on the weights of the edges.
//
// If we assume the following weights:
// - Parent: 1/2
// - Sibling: 1/4
// - Child: 1/8
// - Switch: 1/32
//
// Then we can calculate the importance of all the nodes in the tree.
// The two paths from `8-8` to `3-3` mentioned above give the same end importance in this case, both are shown below.
// ```
// 1-1 # 1 * 1/2 * 1/2 * 1/32 * 1/4 = 1/512
// 2-10 # 1 * 1/2 * 1/2 = 1/4
//
//	3-3 # 1 * 1/2 * 1/2 * 1/32 * 1/8 = 1/1024  or  1 * 1/2 * 1/32 * 1/4 * 1/4 = 1/1024
//	4-6 # 1 * 1/2 * 1/32 * 1/4 = 1/256
//	  5-5 # 1 * 1/2 * 1/32 * 1/4 * 1/32 * 1/8 = 1/65536
//	7-9 # 1 * 1/2 = 1/2
//	  8-8 # 1
//
// ```
func ComputeImportance(tree IndentationTree, criticalLines []codebase.LineNumber, weightsOptional ...TreeImportanceWeights) (map[*IndentationTreeNode]float64, error) {
	if len(criticalLines) == 0 {
		return nil, errors.New("criticalLines must not be empty")
	}
	weights := DefaultTreeImportanceWeights()
	if len(weightsOptional) > 0 {
		weights = weightsOptional[0]
	}
	queue := utils.NewPriorityQueue(InitialQueueItems(tree, criticalLines))
	maxImportanceSeen := make(ImportanceMap)

	for !queue.IsEmpty() {
		item := queue.Pop()
		nodeMap := maxImportanceSeen.Get(item.Node)

		// If we have already seen a higher importance for this node, we can skip it.
		if nodeMap.Get(item.Direction) >= item.Importance {
			continue
		}

		// Update the importance of the node.
		nodeMap[item.Direction] = item.Importance

		// Add the neighbors to the queue.
		for _, neighbor := range neighbors(tree, item.Node, item.Direction, weights) {
			newImportance := item.Importance * neighbor.Importance
			queue.Push(QueueItem{
				Importance: newImportance,
				Node:       neighbor.Node,
				Direction:  neighbor.Direction,
			})
		}
	}

	// Finally, return a map from nodes to the maximum importance.
	var result = make(map[*IndentationTreeNode]float64)
	for node, nodeMap := range maxImportanceSeen {
		result[node] = math.Inf(-1)
		for _, importance := range nodeMap {
			if importance > result[node] {
				result[node] = importance
			}
		}
	}

	return result, nil
}

// InitialQueueItems creates the initial queue items from the critical lines in the tree.
// The initial queue items consist of the parent, sibling, and child nodes of each critical line.
// Each of these items is given an importance of 1.
func InitialQueueItems(tree IndentationTree, criticalLines []codebase.LineNumber) []QueueItem {
	// Build a set of items to avoid duplicates.
	items := make(map[QueueItem]struct{})
	for _, line := range criticalLines {
		for _, node := range tree.GetNodesAtLine(line) {
			for _, direction := range []TreeDirection{Parent, Sibling, Child} {
				item := QueueItem{
					Importance: 1,
					Node:       node,
					Direction:  direction,
				}
				items[item] = struct{}{}
			}
		}
	}
	return slices.Collect(maps.Keys(items))
}

// neighbors returns the neighbors of `node` in `tree`, where `node` was previously found by following an edge in `currentDirection` direction.
// The result is a list of tuples, where the first element is the neighbor node, the second element is the direction in which the neighbor was found, and the third element is the weight of the edge between `node` and the neighbor.
// This weight is used to determine how important the neighbor is.
//
// `currentDirection` is used to determine if the direction switched.
// E.g. a parent's parent is important, but a parent's sibling is less important.
func neighbors(tree IndentationTree, node *IndentationTreeNode, currentDirection TreeDirection, weights TreeImportanceWeights) []QueueItem {
	neighbors := make([]QueueItem, 0)
	addNeighbor := func(neighbor *IndentationTreeNode, direction TreeDirection) {
		neighbors = append(neighbors, QueueItem{
			Node:       neighbor,
			Direction:  direction,
			Importance: direction.Multiplier(currentDirection, weights),
		})
	}

	parent := tree.GetParent(node)
	if parent != nil {
		addNeighbor(parent, Parent)
	}

	for _, sibling := range tree.GetNearestSiblings(node) {
		addNeighbor(sibling, Sibling)
	}

	// Only consider the first and last children
	if len(node.Children) > 0 {
		addNeighbor(node.Children[0], Child)
	}
	if len(node.Children) > 1 {
		addNeighbor(node.Children[len(node.Children)-1], Child)
	}

	return neighbors
}
