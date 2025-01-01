package snippets

import (
	"context"
	"fmt"
	"math"
	"slices"
	"sort"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/codebase"
	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/rendering/contextsset"
	"github.com/github/code-scanning-ai-libraries/v2/rendering/indentation"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/code-scanning-ai-libraries/v2/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
	"github.com/pkoukk/tiktoken-go"
)

// EncodingModel is chosen for consistency with previous implementation, but once we are
// ready to switch to the new implementation, we should update this to use the
// tokenizer for the current model.
const EncodingModel = "cl100k_base"

var enc, encErr = tiktoken.GetEncoding(EncodingModel)

// TokenLength extracts encoding model configuration to a centralized location with other llm code nice ported over from cocofix.
// This returns the number of tokens in the given text.
// The text is first escaped, so that "<|" is not interpreted as a token.
// The text is then tokenized using the "o200k_base" tokenizer for gpt-4o.
// refer: https://github.com/pkoukk/tiktoken-go?tab=readme-ov-file#available-models
func TokenLength(text string) (int, error) {
	escaped := strings.ReplaceAll(text, "<|", "<\\|")
	if encErr != nil {
		return 0, st.EnsureStackTrace(encErr, "failed to get encoding")
	}
	tokens := enc.Encode(escaped, nil, nil)

	return len(tokens), nil
}

// TreeTransversalWeights defines the weights for traversing the indentation tree.
type TreeTransversalWeights struct {
	Parent   float64
	Sibling  float64
	Children float64
	Switch   float64
}

// NodeWithImportance associates an IndentationTreeNode with its importance score.
type NodeWithImportance struct {
	Node       *indentation.IndentationTreeNode
	Importance float64
}

// Weights defines the configuration for rendering code snippets.
type Weights struct {
	MaxContextLines   int
	ContextBudget     int
	DownwardsDistBias int
	TreeTransversal   TreeTransversalWeights
	DistancePower     int
	FillHolesBudget   int
}

// DefaultWeights returns the default weights for rendering code snippets.
func DefaultWeights() Weights {
	return Weights{
		MaxContextLines:   25,
		ContextBudget:     400,
		DownwardsDistBias: 3,
		TreeTransversal: TreeTransversalWeights{
			Parent:   0.6,
			Sibling:  0.9,
			Children: 0.5,
			Switch:   0.1,
		},
		DistancePower:   3,
		FillHolesBudget: 500,
	}
}

// LinesForCodeSnippet selects the lines to include when rendering the code in `set`
// with some context around each snippet. As such, it is exposed as a library method
// for someone wanting to slightly adjust the default rendering exposed in
// `RenderCodeSnippet`. (this is the case for an experiment to use autofix rendering
// style in CCR/autofind)
//
// Which context is kept is determined using indentation trees.
// Lines that are closer in the indentation tree (parents, siblings, children) are more likely to be kept (see `tree_importance.go`).
// Lines where the line number is closer to a snippet are also more likely to be kept (see the `computeDistanceToNodes` function further down).
// Which lines to keep is determined by a final weight computed by `computeFinalImportance`.
//
// The tree-importance and distance calculations are only based on the "main" snippets (the ones that are not part of the preamble).
// The preamble is always kept (see `computeFinalImportance`), but the lines in the preamble are not used to determine the importance of the other lines,
// which means that we don't preserve the context around the preamble.
func LinesForCodeSnippet(ctx context.Context, set *contextsset.ContextsSet, weights *Weights) (map[codebase.LineNumber]bool, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "snippets.LinesForCodeSnippet")
	defer span.End()

	if weights == nil {
		defs := DefaultWeights()
		weights = &defs
	}

	set = set.WithCollapsedGaps()

	lines := strings.Split(set.GetFileContents(), "\n")

	// special-case the case where the entire file is included
	contexts := set.InputContexts()
	if len(contexts) == 1 {
		currentContext := contexts[0]
		if currentContext.StartLine == 1 && int(currentContext.EndLine) == len(lines) {
			result := make(map[codebase.LineNumber]bool)
			for line := codebase.LineNumber(1); line <= currentContext.EndLine; line++ {
				result[line] = true
			}
			return result, nil
		}
	}

	tree := indentation.NewIndentationTreeFromFile(set.GetFileContents())

	lineNumbersInMainSnippet := linesInContexts(set.InputContexts())

	lineNumbersInPreamble := linesInContexts(set.PreambleContexts())

	// traversing the indentation tree to determine the importance of each node
	// 1 for the trees that must be kept, lower for the ones that can be removed
	treeImportance, err := indentation.ComputeImportance(*tree, lineNumbersInMainSnippet)
	if err != nil {
		return nil, st.EnsureStackTrace(err, "failed to compute tree importance")
	}

	// computes the (biased) distances to any of the lines in the main snippets
	distances := computeDistanceToNodes(
		lineNumbersInMainSnippet,
		len(lines),
		tree,
		weights.DownwardsDistBias,
	)

	// computes the final importance of each node
	finalImportance := computeFinalImportance(
		lineNumbersInPreamble,
		treeImportance,
		distances,
		*weights,
	)

	// compute final importance, and sort most important first
	sortedNodesWithImportance := GetSortedNodesWithImportance(tree, finalImportance)

	// Determine nodes to keep
	nodesThatMustBeKept := GetNodesThatMustBeKept(sortedNodesWithImportance)

	budget := weights.ContextBudget + getTokensUsedByNodes(ctx, nodesThatMustBeKept, lines)

	lineCounts := CountLines(sortedNodesWithImportance)

	totalTokensInFile := GetTotalTokens(lines)

	numLinesInSnippets := GetNumLinesInSnippets(nodesThatMustBeKept)

	// remove lines until we are within budget
	// Remove lines until within budget
	currentTokens := totalTokensInFile
	for currentTokens > budget || len(lineCounts) > weights.MaxContextLines+numLinesInSnippets {
		node := RemoveLeastImportantNode(&sortedNodesWithImportance)
		if node == nil {
			return nil, errors.New("no more nodes to remove but budget not met")
		}
		err := UpdateLineCounts(node, lineCounts, lines, &currentTokens)
		if err != nil {
			return nil, st.EnsureStackTrace(err, "failed to update line counts")
		}
	}

	// Determine lines to include
	linesToInclude := make(map[codebase.LineNumber]bool)
	for line := range lineCounts {
		linesToInclude[line] = true
	}

	err = fillInSomeHoles(linesToInclude, lines, tree, finalImportance, *weights)
	if err != nil {
		return nil, st.EnsureStackTrace(err, "failed to fill in holes")
	}

	return linesToInclude, nil
}

// RenderCodeSnippet renders the code in `set` with some context around each snippet.
//
// Which context is kept is determined using indentation trees.
// Lines that are closer in the indentation tree (parents, siblings, children) are more likely to be kept (see `tree_importance.go`).
// Lines where the line number is closer to a snippet are also more likely to be kept (see the `computeDistanceToNodes` function further down).
// Which lines to keep is determined by a final weight computed by `computeFinalImportance`.
//
// The tree-importance and distance calculations are only based on the "main" snippets (the ones that are not part of the preamble).
// The preamble is always kept (see `computeFinalImportance`), but the lines in the preamble are not used to determine the importance of the other lines,
// which means that we don't preserve the context around the preamble.
func RenderCodeSnippet(ctx context.Context, set *contextsset.ContextsSet, weights *Weights) (string, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "snippets.RenderCodeSnippet")
	defer span.End()

	linesToInclude, err := LinesForCodeSnippet(ctx, set, weights)
	if err != nil {
		return "", err
	}

	// Render the final snippet
	lines := strings.Split(set.GetFileContents(), "\n")
	result := RenderFinalSnippet(lines, linesToInclude)
	return result, nil
}

// GetNumLinesInSnippets returns the number of unique lines in the nodes that must be kept.
func GetNumLinesInSnippets(nodes []*indentation.IndentationTreeNode) int {
	lineSet := make(map[codebase.LineNumber]bool)
	for _, node := range nodes {
		lineSet[node.StartLine] = true
		lineSet[node.EndLine] = true
	}
	return len(lineSet)
}

// GetSortedNodesWithImportance sorts nodes based on their importance.
func GetSortedNodesWithImportance(tree *indentation.IndentationTree, finalImportance func(*indentation.IndentationTreeNode) float64) []NodeWithImportance {
	var nodesWithImportance []NodeWithImportance
	for _, node := range tree.GetAllNodes() {
		importance := finalImportance(node)
		nodesWithImportance = append(nodesWithImportance, NodeWithImportance{
			Node:       node,
			Importance: importance,
		})
	}
	// Sort nodes descending by importance
	// Sort nodes in descending order of importance
	sort.SliceStable(nodesWithImportance, func(i, j int) bool {
		return nodesWithImportance[i].Importance > nodesWithImportance[j].Importance
	})
	return nodesWithImportance
}

// GetNodesThatMustBeKept filters nodes with importance equal to 1.
func GetNodesThatMustBeKept(sortedNodes []NodeWithImportance) []*indentation.IndentationTreeNode {
	var nodes []*indentation.IndentationTreeNode
	for _, ni := range sortedNodes {
		if ni.Importance == 1 {
			nodes = append(nodes, ni.Node)
		}
	}
	return nodes
}

// UpdateLineCounts updates the line counts and current tokens after removing a node.
func UpdateLineCounts(
	node *indentation.IndentationTreeNode,
	lineCounts map[codebase.LineNumber]int,
	lines []string,
	currentTokens *int,
) error {
	linesToRemove := []codebase.LineNumber{node.StartLine}
	if node.StartLine != node.EndLine {
		linesToRemove = append(linesToRemove, node.EndLine)
	}
	for _, line := range linesToRemove {
		if count, exists := lineCounts[line]; exists {
			if count <= 1 {
				delete(lineCounts, line)
				tokenCount, err := TokenLength(lines[line-1])
				if err != nil {
					return st.EnsureStackTracef(err, "error computing token length for line %d", line)
				}
				*currentTokens -= tokenCount + 1 // +1 for the newline
			} else {
				lineCounts[line] = count - 1
			}
		}
	}
	return nil
}

// RemoveLeastImportantNode removes and returns the least important node from the sorted list.
func RemoveLeastImportantNode(sortedNodes *[]NodeWithImportance) *indentation.IndentationTreeNode {
	if len(*sortedNodes) == 0 {
		return nil
	}
	// Remove the last element (least important)
	ni := (*sortedNodes)[len(*sortedNodes)-1]
	*sortedNodes = (*sortedNodes)[:len(*sortedNodes)-1]
	return ni.Node
}

// GetTotalTokens calculates the total number of tokens in the file.
func GetTotalTokens(lines []string) int {
	total := 0
	for _, line := range lines {
		tokenCount, err := TokenLength(line)
		if err != nil {
			// Handle error appropriately, possibly skipping this line
			continue
		}
		total += tokenCount + 1 // +1 for the newline
	}
	return total
}

// RenderFinalSnippet renders the final snippet with "[...]" in between excluded lines.
func RenderFinalSnippet(lines []string, linesToInclude map[codebase.LineNumber]bool) string {
	var result strings.Builder
	needsEllipsis := false
	for line := codebase.LineNumber(1); line <= codebase.LineNumber(len(lines)); line++ {
		if linesToInclude[line] {
			if needsEllipsis {
				_, _ = result.WriteString("[...]\n")
				needsEllipsis = false
			}
			trimmedLine := strings.TrimRight(lines[line-1], "\r")
			_, _ = result.WriteString(fmt.Sprintf("%d: %s\n", line, trimmedLine))
		} else if line != 1 {
			needsEllipsis = true
		}
	}

	// If the last line was not included, add an ellipsis.
	if !linesToInclude[codebase.LineNumber(len(lines))] {
		_, _ = result.WriteString("[...]\n")
	}

	// Remove any trailing newline.
	final := strings.TrimRight(result.String(), "\n")
	return final
}

// CountLines counts how many times each line is referenced by the nodes.
func CountLines(sortedNodes []NodeWithImportance) map[codebase.LineNumber]int {
	lineCounts := make(map[codebase.LineNumber]int)
	for _, ni := range sortedNodes {
		node := ni.Node
		if node.StartLine == node.EndLine {
			lineCounts[node.StartLine]++
		} else {
			lineCounts[node.StartLine]++
			lineCounts[node.EndLine]++
		}
	}
	return lineCounts
}

// Uses up to `WEIGHTS.FILL_HOLES_BUDGET` to fill in some otherwise elided holes in the code-snippet that's about to be rendered.
// fillInSomeHoles uses up to `FillHolesBudget` to fill in some otherwise elided holes in the code-snippet that's about to be rendered.
func fillInSomeHoles(
	linesToInclude map[codebase.LineNumber]bool,
	lines []string,
	tree *indentation.IndentationTree,
	finalImportance func(node *indentation.IndentationTreeNode) float64,
	weights Weights,
) error {
	lineImportances := make(map[codebase.LineNumber]float64)
	for _, node := range tree.GetAllNodes() {
		importance := finalImportance(node)
		lineImportances[node.StartLine] = math.Max(importance, lineImportances[node.StartLine])
		lineImportances[node.EndLine] = math.Max(importance, lineImportances[node.EndLine])
	}

	var holes [][2]codebase.LineNumber
	for line := codebase.LineNumber(1); line <= codebase.LineNumber(len(lines)); line++ {
		if !linesToInclude[line] {
			if len(holes) > 0 && holes[len(holes)-1][1] == line-1 {
				holes[len(holes)-1][1] = line
			} else {
				holes = append(holes, [2]codebase.LineNumber{line, line})
			}
		}
	}

	holeImportance := make(map[[2]codebase.LineNumber]float64)
	for _, hole := range holes {
		maxImp := 0.0
		for line := hole[0]; line <= hole[1]; line++ {
			if imp, exists := lineImportances[line]; exists && imp > maxImp {
				maxImp = imp
			}
		}
		holeImportance[hole] = maxImp
	}

	tokensInHole := make(map[[2]codebase.LineNumber]int)
	for _, hole := range holes {
		holeLines := lines[hole[0]-1 : hole[1]]
		text := strings.Join(holeLines, "\n")
		tokenCount, err := TokenLength(text)
		if err != nil {
			return st.EnsureStackTracef(err, "error computing token length for hole %v", hole)
		}
		tokensInHole[hole] = tokenCount
	}

	type Hole struct {
		Lines      [2]codebase.LineNumber
		Importance float64
		Tokens     int
	}

	var holeList []Hole
	for hole, imp := range holeImportance {
		holeList = append(holeList, Hole{
			Lines:      hole,
			Importance: imp,
			Tokens:     tokensInHole[hole],
		})
	}

	sort.Slice(holeList, func(i, j int) bool {
		return (holeList[i].Importance / float64(holeList[i].Tokens)) > (holeList[j].Importance / float64(holeList[j].Tokens))
	})

	tokenBudgetLeft := weights.FillHolesBudget
	for _, hole := range holeList {
		if hole.Tokens <= tokenBudgetLeft {
			for line := hole.Lines[0]; line <= hole.Lines[1]; line++ {
				linesToInclude[line] = true
			}
			tokenBudgetLeft -= hole.Tokens
		}
	}
	return nil
}

// Gets a importance (number between 0 and 1) for each node to determine how important it is.
// Higher number means more likely to be included in the rendered code.
// Importance 1 means it must be included.
// We do the main computations based on the "main" snippets, i.e. the ones that are not in the preamble.
// The distance calculations and tree-importance are done on those main snippets. That way we don't expand beyond the preamble.
// But the exact lines for the preamble are still important, so we add them to the final result by giving them importance 1.

func computeFinalImportance(
	lineNumbersInPreamble []codebase.LineNumber,
	treeImportance map[*indentation.IndentationTreeNode]float64,
	distances map[*indentation.IndentationTreeNode]float64,
	weights Weights,
) func(node *indentation.IndentationTreeNode) float64 {
	preambleSet := make(map[codebase.LineNumber]bool)
	for _, line := range lineNumbersInPreamble {
		preambleSet[line] = true
	}

	return func(node *indentation.IndentationTreeNode) float64 {
		if preambleSet[node.StartLine] {
			return 1.0
		}
		imp, exists := treeImportance[node]
		if !exists {
			imp = 0.0
		}
		dist, exists := distances[node]
		if !exists {
			dist = math.Inf(1)
		}
		return imp / math.Pow(1.0+dist, float64(weights.DistancePower))
	}
}

// getTokensUsedByNodes estimates the total number of tokens used by the start and end lines of the given nodes.
func getTokensUsedByNodes(ctx context.Context, nodes []*indentation.IndentationTreeNode, lines []string) int {
	lineNumbers := make(map[codebase.LineNumber]bool)
	for _, node := range nodes {
		lineNumbers[node.StartLine] = true
		lineNumbers[node.EndLine] = true
	}

	total := 0
	for line := range lineNumbers {
		if line >= 1 && int(line) <= len(lines) {
			tokenCount, err := TokenLength(lines[line-1])
			if err != nil {
				enhancedctx.Logger(ctx).WithError(err).Error("Error computing token length for line", kvp.Int("gh.autofix.line_number", int(line)))
				return 0
			}
			total += tokenCount + 1 // +1 for the newline
		}
	}
	return total
}

// Computes the distance from any of the lines contained in `linesInMainSnippets`
// to the start/end line (whichever is closer) of a node in the tree.
//
// The result is a mapping from the nodes to their distance.
//
// The `downwardsBias` modifies the effective distance that going one line down
// counts as. The distance for one step upwards is always 1.

func computeDistanceToNodes(
	linesInMainSnippets []codebase.LineNumber,
	numLinesInFile int,
	tree *indentation.IndentationTree,
	downwardsBias int,
) map[*indentation.IndentationTreeNode]float64 {
	distances := map[codebase.LineNumber]float64{}
	for _, line := range linesInMainSnippets {
		distances[line] = 0
	}

	queue := utils.NewPriorityQueueFunc(
		linesInMainSnippets,
		// shortest distances first
		func(a codebase.LineNumber) float64 {
			return -distances[a]
		},
	)

	for queue.Len() > 0 {
		line := queue.Pop()
		distance, found := distances[line]
		if !found {
			continue
		}

		neighbors := []struct {
			neighbor      codebase.LineNumber
			deltaDistance int
		}{
			{line - 1, 1},             // up
			{line + 1, downwardsBias}, // down
		}

		for _, n := range neighbors {
			if n.neighbor >= 1 && int(n.neighbor) <= numLinesInFile {
				currentDist, exists := distances[n.neighbor]
				newDist := distance + float64(n.deltaDistance)
				if !exists || newDist < currentDist {
					distances[n.neighbor] = newDist
					queue.Push(n.neighbor)
				}
			}
		}
	}

	result := map[*indentation.IndentationTreeNode]float64{}
	for _, node := range tree.GetAllNodes() {
		minDist := math.Inf(+1)
		if dist, exists := distances[node.StartLine]; exists {
			minDist = min(dist, minDist)
		}
		if dist, exists := distances[node.EndLine]; exists {
			minDist = min(dist, minDist)
		}
		if !math.IsInf(minDist, +1) {
			result[node] = minDist
		}
	}
	return result
}

// Makes a set of all the line numbers contained in `snippets`.
func linesInContexts(snippets []codebase.ContextLines) []codebase.LineNumber {
	linesSet := map[codebase.LineNumber]bool{}
	for _, snippet := range snippets {
		for line := snippet.StartLine; line <= snippet.EndLine; line++ {
			linesSet[line] = true
		}
	}
	ret := utils.Keys(linesSet)
	slices.Sort(ret)
	return ret
}
