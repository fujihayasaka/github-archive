// Package indentation provides functionality to work with indentation trees in code files.
package indentation

import (
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/codebase"
	"github.com/github/code-scanning-ai-libraries/v2/utils"
)

// IndentationTreeNode represents a node in an indentation tree.
//
//nolint:revive // exported name "stutters" across package boundary; kept for API stability
type IndentationTreeNode struct {
	StartLine codebase.LineNumber
	EndLine   codebase.LineNumber
	Children  []*IndentationTreeNode
}

// IndentationTree represents an indentation tree.
//
//nolint:revive // exported name "stutters" across package boundary; kept for API stability
type IndentationTree struct {
	LineToNodes map[codebase.LineNumber]map[*IndentationTreeNode]struct{}
	Parents     map[*IndentationTreeNode]*IndentationTreeNode
	TopNodes    []*IndentationTreeNode
}

/*
NewIndentationTree creates a new indentation tree.

Represents a tree based view of a file.
Each node represents a block of code, where the start and end lines both have the same indentation,
and everything in between is indented more than the start and end lines.

A file consists of a list of top-level nodes.
Blank lines are considered to have the same indentation as the next non-blank line.

Start and end lines are inclusive and 1-indexed.
The line numbers for two nodes usually don't overlap, but there are some exceptions:
 1. If there is just 1 less indented line between two more indented lines. Then the end of one node will be the same as the start of the next.
 2. At the end of the file, if the last line is indented, then it will count both as the end and "middle" of a node.
*/
func NewIndentationTree(topNodes []*IndentationTreeNode) *IndentationTree {
	tree := &IndentationTree{
		LineToNodes: make(map[codebase.LineNumber]map[*IndentationTreeNode]struct{}),
		Parents:     make(map[*IndentationTreeNode]*IndentationTreeNode),
		TopNodes:    topNodes,
	}

	for _, node := range tree.GetAllNodes() {
		addLine(tree, node, node.StartLine)
		addLine(tree, node, node.EndLine)

		for _, child := range node.Children {
			tree.Parents[child] = node
		}
	}

	return tree
}

// addLine adds a node to the LineToNodes map for a specific line.
func addLine(tree *IndentationTree, node *IndentationTreeNode, line codebase.LineNumber) {
	if _, exists := tree.LineToNodes[line]; !exists {
		tree.LineToNodes[line] = make(map[*IndentationTreeNode]struct{})
	}
	tree.LineToNodes[line][node] = struct{}{}
}

// AddNode adds a new node to the tree.
func (tree *IndentationTree) AddNode(startLine, endLine codebase.LineNumber) *IndentationTreeNode {
	node := &IndentationTreeNode{
		StartLine: startLine,
		EndLine:   endLine,
		Children:  []*IndentationTreeNode{},
	}

	for line := startLine; line <= endLine; line++ {
		if _, exists := tree.LineToNodes[line]; !exists {
			tree.LineToNodes[line] = make(map[*IndentationTreeNode]struct{})
		}
		tree.LineToNodes[line][node] = struct{}{}
	}

	tree.TopNodes = append(tree.TopNodes, node)
	return node
}

// SetParent sets the parent of a node.
func (tree *IndentationTree) SetParent(child, parent *IndentationTreeNode) {
	tree.Parents[child] = parent
	parent.Children = append(parent.Children, child)
}

// GetParent returns the parent of a node.
func (tree *IndentationTree) GetParent(node *IndentationTreeNode) *IndentationTreeNode {
	return tree.Parents[node]
}

// GetNodesAtLine returns the nodes at a given line.
func (tree *IndentationTree) GetNodesAtLine(line codebase.LineNumber) []*IndentationTreeNode {
	nodes := []*IndentationTreeNode{}
	for node := range tree.LineToNodes[line] {
		nodes = append(nodes, node)
	}
	return nodes
}

// GetAllNodes returns all nodes in the tree.
func (tree *IndentationTree) GetAllNodes() []*IndentationTreeNode {
	var result []*IndentationTreeNode
	visited := make(map[*IndentationTreeNode]struct{})
	var recurse func(nodes []*IndentationTreeNode)
	recurse = func(nodes []*IndentationTreeNode) {
		for _, node := range nodes {
			if _, seen := visited[node]; !seen {
				visited[node] = struct{}{}
				result = append(result, node)
				recurse(node.Children)
			}
		}
	}
	recurse(tree.TopNodes)
	return result
}

// GetNearestSiblings returns the nearest siblings of a node.
// This includes the nodes immediately above and below the node, if they exist.
// TODO: Consider renaming this to GetImmediateSiblings to use more standard nomenclature.
func (tree *IndentationTree) GetNearestSiblings(node *IndentationTreeNode) []*IndentationTreeNode {
	parent := tree.GetParent(node)
	var allSiblings []*IndentationTreeNode
	if parent == nil {
		allSiblings = tree.TopNodes
	} else {
		allSiblings = parent.Children
	}

	// Find the index of the node in the list of siblings
	index := 0
	for i, sibling := range allSiblings {
		if sibling == node {
			index = i
			break
		}
	}

	// Only return the siblings immediately above or below the node.
	nearestSiblings := []*IndentationTreeNode{}
	if index > 0 {
		nearestSiblings = append(nearestSiblings, allSiblings[index-1])
	}
	if index < len(allSiblings)-1 {
		nearestSiblings = append(nearestSiblings, allSiblings[index+1])
	}
	return nearestSiblings
}

// NewIndentationTreeFromFile creates an indentation tree from the contents of a file.
func NewIndentationTreeFromFile(fileContents string) *IndentationTree {
	lines := strings.Split(fileContents, "\n")
	nodes := buildIndentationNodes(lines, 0, len(lines)-1)
	return NewIndentationTree(nodes)
}

// buildIndentationNodes builds the indentation tree nodes for the given lines.
// start and end are 0-indexed and inclusive
func buildIndentationNodes(lines []string, start, end int) []*IndentationTreeNode {
	var nodeList []*IndentationTreeNode
	i := start

	for i <= end {
		startLine := codebase.LineNumber(i + 1)
		startIndent := utils.GetEffectiveIndentation(lines, i)

		// Check if it should just be a single-line tree
		if (i < end && utils.GetEffectiveIndentation(lines, i+1) <= startIndent) || i == end {
			nodeList = append(nodeList, &IndentationTreeNode{
				StartLine: startLine,
				EndLine:   startLine,
				Children:  []*IndentationTreeNode{},
			})
			i++
			continue
		}

		// Walk to the end of this node
		i++
		for i <= end &&
			// blank lines are included in the block, because otherwise we might not include the end-bracket for some blocks (see the `should parse two top-level functions correctly, with blanks` test).
			// this might not be optimal for purely indentation-based languages (e.g. Python), but to do better we would need special treatment of e.g. the `}` character.
			(utils.GetEffectiveIndentation(lines, i) > startIndent || utils.IsBlank(lines[i])) {
			i++
		}

		endLine := codebase.LineNumber(i + 1)

		// Create a new node with the current start and end lines
		// Recursively handles children by calling fromLines on the lines between startLine and endLine
		nodeList = append(nodeList, &IndentationTreeNode{
			StartLine: startLine,
			EndLine:   endLine,
			Children:  buildIndentationNodes(lines, int(startLine), int(endLine)-2), // `startLine` and `endLine` are 1-indexed and inclusive. The arguments are 0-indexed and inclusive.
		})

		if i < end && utils.GetEffectiveIndentation(lines, i+1) > startIndent {
			// If the next line after currentLine is more indented, re-use the end-line of the current node
			// as the start-line of the next node
		} else {
			// Otherwise, start at the next line
			i++
		}
	}

	// Check if the end of the last node is beyond the end of the file, and in that case decrement the end-line
	if len(nodeList) > 0 && nodeList[len(nodeList)-1].EndLine > codebase.LineNumber(len(lines)) {
		nodeList[len(nodeList)-1].EndLine--
	}

	return nodeList
}

// LinesInTree returns the lines of code in an indentation tree.
func LinesInTree(node *IndentationTreeNode, lines []string) []string {
	// subtract 1 because lines are 0-indexed
	start := int(node.StartLine) - 1
	// subtract 1 because lines are 0-indexed
	// add 1 because end lines are inclusive, but slices are exclusive
	end := int(node.EndLine)
	if start < 0 {
		start = 0
	}
	if end > len(lines) {
		end = len(lines)
	}
	return lines[start:end]
}
