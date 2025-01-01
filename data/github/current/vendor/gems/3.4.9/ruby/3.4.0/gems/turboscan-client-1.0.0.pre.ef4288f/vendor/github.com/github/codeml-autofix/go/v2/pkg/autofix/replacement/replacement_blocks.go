// Package replacement provides functionality for processing replacement blocks in code.
package replacement

import (
	"context"
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/snippets"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/go-errors/errors"

	replacement_lib "github.com/github/code-scanning-ai-libraries/v2/replacement"
)

// ProcessReplacementBlocksSection processes the replacement blocks section of the model response to extract the
// edits we want to make to all files, adjust them if necessary, and
// normalize them.
//
// The basic structure of the replacement blocks section is:
// `````
// file:src/example.js
// original lines:
// ```
// <original lines>
// ```
//
// replacement lines:
// ```
// <replacement lines>
// ```
//
// ...
//
// file:src/example2.js
// ...
// `````
func ProcessReplacementBlocksSection(ctx context.Context, replacementBlocksStr string, seenFiles []string, alert *alerts.Alert) ([]editcommands.FileEdit, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "replacement.ProcessReplacementBlocksSection")
	defer span.End()

	if ctxErr := autofix.NewErrorFromContextErr(ctx, "Context canceled while processing replacement blocks"); ctxErr != nil {
		autofix.ReportErrorToTelemetry(ctx, ctxErr)
		return nil, ctxErr
	}

	editsForFile := make(map[string]*[]editcommands.EditCommand)
	codeBase := alert.Context.File().Codebase

	blocks, err := parseBlocks(ctx, replacementBlocksStr, seenFiles)
	if err != nil {
		if !autofix.IsErrorOfCategory(err, autofix.ErrorCategoryParsing) || len(blocks) == 0 {
			return nil, err
		}
		enhancedctx.Logger(ctx).Warn("Continuing with partial blocks despite parsing error",
			kvp.String("error", err.Error()))
	}
	for i := range blocks {
		block := &blocks[i]

		fileName := block.fileName
		fileName, err := normalizeFileName(ctx, fileName, seenFiles, alert)

		if err != nil {
			continue // err is returned by `normalizeFileName` if the file should be skipped
		}

		file, err := codeBase.GetFile(fileName)
		if err != nil {
			return nil, autofix.NewFileNotFoundError(
				fmt.Sprintf("Failed to get file %s", fileName),
				err,
				fileName)
		}
		fileContents, err := file.ReadContents()
		if err != nil {
			return nil, err
		}
		fileContents = utils.NormalizeLineEndings(fileContents)

		_, containsKey := editsForFile[fileName]
		if !containsKey {
			editsForFile[fileName] = &[]editcommands.EditCommand{}
		}
		var edits = editsForFile[fileName]

		fileFromCodeBase, err := codeBase.GetFile(fileName)
		if err != nil {
			return nil, err
		}

		edit, err := applyReplacementBlock(
			ctx,
			block.before,
			block.after,
			fileContents,
			fileFromCodeBase,
			alert,
		)

		if err == nil {
			newEditsForFile := append((*editsForFile[fileName]), edit...)
			editsForFile[fileName] = &newEditsForFile
		}
		if err != nil {
			if !autofix.IsErrorOfType(err, autofix.ErrorTypeBlockMismatch) ||
				len(*edits) == 0 {
				return nil, err
			}

			*edits = append(*edits, edit...)
			codeBaseFile, err := codeBase.GetFile(fileName)
			if err != nil {
				return nil, err
			}

			newEdits, err := applyReplacementBlockWithPreviousChanges(
				ctx,
				*edits,
				fileContents,
				*block,
				codeBaseFile,
				alert,
			)
			if err != nil {
				return nil, err
			}

			// completely replace the edits for this file
			*editsForFile[fileName] = newEdits
		}
	}

	if len(editsForFile) == 0 {
		err := autofix.NewNoReplacementBlockError(
			"Failed to extract any replacement blocks",
			nil,
			"")
		autofix.ReportErrorToTelemetry(ctx, err)
		return []editcommands.FileEdit{}, err
	}

	result := []editcommands.FileEdit{}

	for fileName, editCommands := range editsForFile {
		file, err := codeBase.GetFile(fileName)
		if err != nil {
			return nil, err
		}

		normalizedEditCommands, err := normalizeEditCommands(file, *editCommands)
		if err != nil {
			return nil, err
		}
		result = append(result, editcommands.FileEdit{
			FilePath:     fileName,
			EditCommands: editcommands.NewEditCommands(normalizedEditCommands),
		})
	}
	return result, nil
}

// applyReplacementBlockWithPreviousChanges Applies the replacement block to the file,
// where it's assumed that the "before" block searches within content where `existingEdits` have already been applied.
// Returns a set of edit commands that edits the original file to the final edited file.
func applyReplacementBlockWithPreviousChanges(
	ctx context.Context,
	existingEdits []editcommands.EditCommand,
	fileContents string,
	block Block,
	file codebase.File,
	alert *alerts.Alert,
) ([]editcommands.EditCommand, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "replacement.ApplyReplacementBlockWithPreviousChanges")
	defer span.End()

	newFileContents := editcommands.NewEditCommands(existingEdits).Apply(fileContents)

	editsForBlock, err := applyReplacementBlock(
		ctx,
		block.before,
		block.after,
		newFileContents,
		file,
		alert,
	)

	if err != nil {
		return nil, err
	}

	newerFileContents := editcommands.NewEditCommands(editsForBlock).Apply(newFileContents)

	finalEdits := ParseEditCommandsFromContents(
		fileContents,
		newerFileContents,
	)

	return finalEdits, nil
}

// normalizeEditCommands applies the edit commands to the file, and the parses a set of edit-commands from the diff.
// This is done to simplify/normalize the edit-commands, so they are easier to test.
func normalizeEditCommands(file codebase.File, editCommands []editcommands.EditCommand) ([]editcommands.EditCommand, error) {
	orgContents, err := file.ReadContents()
	if err != nil {
		return nil, autofix.NewParsingError(
			fmt.Sprintf("Failed to read file contents for %s", file.Path),
			err)
	}

	// Normalize a set of edit-commands that are assumed to not overlap.
	normalizeNonOverlappingEdits := func(editCommands []editcommands.EditCommand) []editcommands.EditCommand {
		newContents := editcommands.NewEditCommands(editCommands).Apply(orgContents)
		return ParseEditCommandsFromContents(orgContents, newContents)
	}

	// first normalize each edit-command individually. This can matter if multiple edit-commands span (and replace) the same section of the file.
	// this first normalization makes sure that each individual edit-command is as
	// small as possible.
	individuallyNormalizedEditCommands := make([]editcommands.EditCommand, 0, len(editCommands))
	for _, e := range editCommands {
		individuallyNormalizedEditCommands = append(individuallyNormalizedEditCommands, normalizeNonOverlappingEdits([]editcommands.EditCommand{e})...)
	}

	// now normalize again, but all edit-commands together.
	globallyNormalizedEditCommands := normalizeNonOverlappingEdits(individuallyNormalizedEditCommands)
	return globallyNormalizedEditCommands, nil
}

// BlockState represents the state of a replacement block.
type BlockState int

const (
	// Named is the initial state, where the block has been named but not started.
	Named BlockState = iota
	// BeforeAnnounced is the state before the block has been announced.
	BeforeAnnounced
	// BeforeStarted is the state after the block has been announced but before it has started.
	BeforeStarted
	// BeforeFinished is the state after the block has started but before it has finished.
	BeforeFinished
	// AfterAnnounced is the state after the block has finished and the replacement lines have been announced.
	AfterAnnounced
	// AfterStarted is the state after the replacement lines have started but before they have finished.
	AfterStarted
	// AfterFinished is the state after the replacement lines have finished.
	AfterFinished
)

// String returns a string representation of the BlockState.
func (b BlockState) String() string {
	switch b {
	case Named:
		return "Named"
	case BeforeAnnounced:
		return "BeforeAnnounced"
	case BeforeStarted:
		return "BeforeStarted"
	case BeforeFinished:
		return "BeforeFinished"
	case AfterAnnounced:
		return "AfterAnnounced"
	case AfterStarted:
		return "AfterStarted"
	case AfterFinished:
		return "AfterFinished"
	default:
		panic("Unknown BlockState")
	}
}

// Block represents a replacement block in the model response.
type Block struct {
	before   string
	after    string
	state    BlockState
	fileName string
	//  seenLineNumbers indicating whether we have seen at least one line with a leading
	//  line number since starting to scan a code block.
	//
	//  We use this to handle cases where the model forgets to close the code block with
	//  a ``` line: if we see a blank line after we have seen a line number, we assume
	//  that the code block has ended.
	seenLineNumbers bool
}

// NewBlock creates a new Block with the given file name.
func NewBlock(fileName string) *Block {
	return &Block{
		before:          "",
		after:           "",
		state:           Named,
		fileName:        fileName,
		seenLineNumbers: false,
	}
}

// mayTerminateBlock
//
// Heuristic to determine if a replacement block has ended without a closing ```
// line.
//
// The model sometimes forgets the closing ```; it's hard to tell when this
// happens in general and there are many ambiguous cases, but one relatively
// clear-cut case is when we are parsing a block of lines with line numbers and
// suddenly encounter a non-empty, non-ellipsis line without a line number; in
// this case, we assume that the block has ended.
func (b *Block) mayTerminateBlock(line string) bool {
	return b.seenLineNumbers &&
		strings.TrimSpace(line) != "" &&
		!replacement_lib.IsEllipsis(line) &&
		!snippets.InitialLineNumberRegex.MatchString(line)
}

var startsReplacementSectionRegex = regexp.MustCompile(`(?i)^\s*#*\s*file:`)

func startsReplacementSection(line string) bool {
	matched := startsReplacementSectionRegex.MatchString(line)
	return matched
}

func (b *Block) isEmpty() bool {
	return b.state == Named
}

func (b *Block) isFinished() bool {
	return b.state == AfterFinished
}

func (b *Block) canBeTerminated() bool {
	return b.isEmpty() || b.isFinished()
}

// is called on lines that are known to be part of the block
func (b *Block) consumeLine(line string) error {
	normalizedLine := strings.ToLower(strings.TrimSpace(line))
	switch b.state {
	// the file has been named, we have not yet seen any replacement blocks
	case Named:
		if normalizedLine == "original lines:" {
			b.state = BeforeAnnounced
		}
		// else, assume it's a blank line for comments or whatever

	// we have seen the `original lines:` line, but not the start of a block
	case BeforeAnnounced:
		if strings.HasPrefix(normalizedLine, "```") {
			b.state = BeforeStarted
			b.seenLineNumbers = false
		} else {
			return autofix.NewParsingError(
				"Unexpected line in replacement blocks during "+b.state.String()+" state",
				errors.Errorf("got `%s`", line))
		}
	// we have seen the start of the original lines, and we are consuming the lines in the block
	case BeforeStarted:
		if strings.HasPrefix(normalizedLine, "```") {
			b.state = BeforeFinished
		} else if b.mayTerminateBlock(line) {
			b.state = BeforeFinished
			// need to reprocess this line
			return b.consumeLine(line)
		} else {
			if snippets.InitialLineNumberRegex.MatchString(line) {
				b.seenLineNumbers = true
			}
			b.before += line
		}
	// we have seen the end of the original lines, but not the start of the replacement lines
	case BeforeFinished:
		if normalizedLine == "replacement lines:" {
			b.state = AfterAnnounced
		}
		// else, assume it's a blank line or comments or whatever

	// we have seen the `replacement lines:` line, but not the start of a block
	case AfterAnnounced:
		if strings.HasPrefix(normalizedLine, "```") {
			b.state = AfterStarted
			b.seenLineNumbers = false
		} else {
			return autofix.NewParsingError(
				"Unexpected line in replacement blocks during "+b.state.String()+" state",
				errors.Errorf("got `%s`", line))
		}
	// we have seen the start of the replacement lines, and we are consuming the lines in the block
	case AfterStarted:
		if strings.HasPrefix(normalizedLine, "```") {
			b.state = AfterFinished
		} else if b.mayTerminateBlock(line) {
			b.state = AfterFinished
			// need to reprocess this line
			return b.consumeLine(line)
		} else {
			if snippets.InitialLineNumberRegex.MatchString(line) {
				b.seenLineNumbers = true
			}
			b.after += line
		}
	// we have seen the end of the replacement lines, but not the start of the next block
	case AfterFinished:
		// assume it's a blank line or comments or whatever
		break
	default:
		return autofix.NewParsingError(
			fmt.Sprintf("Unexpected block state: %s", b.state.String()),
			errors.Errorf("processing line `%s`", line))
	}
	return nil
}

func parseBlocks(ctx context.Context, output string, seenFiles []string) ([]Block, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "replacement.ParseBlocks")
	defer span.End()

	// process output in blocks
	var currentBlock *Block = nil
	blocks := []Block{}

	startBlock := func(line string) error {
		if currentBlock != nil && !currentBlock.canBeTerminated() {
			return autofix.NewBlockMismatchError(
				"Unexpected block state - block left in incorrect state",
				errors.New("block in incorrect state"),
				currentBlock.fileName)
		}

		// `line` is either of the form `file:<filename>` or `#### File: <filename>`
		filename := strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
		blocks = append(blocks, *NewBlock(filename))
		currentBlock = &blocks[len(blocks)-1]

		return nil
	}

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line += "\n"

		if currentBlock == nil &&
			strings.HasPrefix(line, "original lines:") &&
			len(seenFiles) == 1 {
			// directly starting with original lines, and there is only 1 file, so it's unambiguous
			err := startBlock("file:" + seenFiles[0])
			if err != nil {
				return nil, err
			}
		}

		// check if this is the start of a new replacement section
		if startsReplacementSection(line) {
			// if we don't have a current block or the current block is finished or empty, start a new block
			if currentBlock == nil || currentBlock.canBeTerminated() {
				err := startBlock(line)
				if err != nil {
					return nil, err
				}
				continue
			}
		}

		if currentBlock != nil && currentBlock.isFinished() && strings.HasPrefix(line, "original lines:") {
			// we actually need a new block for the same file
			blocks = append(blocks, *NewBlock(currentBlock.fileName))
			currentBlock = &blocks[len(blocks)-1]
		}
		if currentBlock != nil {
			err := currentBlock.consumeLine(line)
			if err != nil {
				return nil, err
			}
		}
	}

	// filter out empty blocks
	blocks = utils.Filter(blocks, func(block Block) bool { return !block.isEmpty() })

	if len(blocks) == 0 {
		enhancedctx.Logger(ctx).Warn("No replacement blocks found")
	} else if blocks[len(blocks)-1].state == AfterStarted {
		// the model sometimes forgets to add the final ``` to the last block
		blocks[len(blocks)-1].state = AfterFinished
	} else if !blocks[len(blocks)-1].isFinished() {
		return nil, autofix.NewBlockMismatchError(
			"Unexpected block state - block not properly finished: "+blocks[len(blocks)-1].state.String(),
			errors.New("block not properly finished"),
			blocks[len(blocks)-1].fileName)
	}

	for i := range blocks {
		// remove trailing newline from before and after:
		blocks[i].before = strings.TrimRight(blocks[i].before, "\n")
		blocks[i].after = strings.TrimRight(blocks[i].after, "\n")
	}

	return blocks, nil
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func applyReplacementBlock(
	ctx context.Context,
	beforeBlock string,
	afterBlock string,
	replacementFileContents string,
	file codebase.File,
	alert *alerts.Alert,
	minLineOptional ...codebase.LineNumber,
) ([]editcommands.EditCommand, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "replacement.ApplyReplacementBlock")
	defer span.End()

	if ctxErr := autofix.NewErrorFromContextErr(ctx, "Context canceled while applying replacement block"); ctxErr != nil {
		return nil, ctxErr
	}

	minLine := codebase.LineNumber(-1)
	if len(minLineOptional) > 0 {
		minLine = minLineOptional[0]
	}

	if beforeBlock == afterBlock ||
		removeLineNumbers(beforeBlock) == removeLineNumbers(afterBlock) {
		return []editcommands.EditCommand{}, nil
	}

	// if ellipsis in the middle. Split original and replacement blocks on ellipsis and apply recursively.
	if utils.Some(strings.Split((beforeBlock+"\n"+afterBlock), "\n"), replacement_lib.IsEllipsis) {
		splitBlocksBefore := replacement_lib.SplitOnEllipses(beforeBlock)
		splitBlocksAfter := replacement_lib.SplitOnEllipses(afterBlock)

		if len(splitBlocksBefore) != len(splitBlocksAfter) {
			return nil, autofix.NewEllipsisMismatchError(
				"Different number of ellipses in before and after blocks",
				nil,
				file.Path)
		}

		return applySplitBlocks(
			ctx,
			splitBlocksBefore,
			splitBlocksAfter,
			file,
			replacementFileContents,
			alert,
		)
	}

	// if the blocks contain non-consecutive line numbers, split them out and apply recursively.
	nonConsecutiveBlocks, err := splitNonConsecutiveLines(beforeBlock)
	if err != nil {
		return nil, err
	}
	if len(nonConsecutiveBlocks) > 1 {
		splitBlocksBefore, errBefore := splitNonConsecutiveLines(beforeBlock)
		if errBefore != nil {
			return nil, errBefore
		}
		splitBlocksAfter, errAfter := splitNonConsecutiveLines(afterBlock)
		if errAfter != nil {
			return nil, errAfter
		}

		if len(splitBlocksBefore) != len(splitBlocksAfter) {
			return nil, autofix.NewBlockMismatchError(
				"different number of non-consecutive lines in before and after blocks",
				errors.New("block mismatch"),
				file.Path)
		}

		return applySplitBlocks(
			ctx,
			splitBlocksBefore,
			splitBlocksAfter,
			file,
			replacementFileContents,
			alert,
		)
	}

	shownLines, err := snippets.GetShownLinesForFile(ctx, alert, file)
	if err != nil {
		return []editcommands.EditCommand{}, autofix.NewParsingError(
			fmt.Sprintf("failed to get shown lines for file %s", file.Path),
			err)
	}
	shownLines = utils.Filter(shownLines, func(line codebase.LineNumber) bool {
		return line >= minLine
	})

	bestMatch, err := FindBestBlockMatch(beforeBlock, replacementFileContents, afterBlock, shownLines, file)
	if err != nil {
		// Check if it's an AutofixError before reporting to telemetry
		if autofixErr, ok := err.(autofix.AutofixError); ok {
			if autofix.IsErrorOfType(autofixErr, autofix.ErrorTypeBlockMismatch) {
				autofix.ReportErrorToTelemetry(ctx, autofixErr)
			}
		}
		return nil, err
	}

	return []editcommands.EditCommand{editcommands.NewReplace(
		bestMatch.start,
		bestMatch.end,
		strings.Split(bestMatch.afterBlock, "\n"))}, nil
}

func applySplitBlocks(
	ctx context.Context,
	splitBlocksBefore []string,
	splitBlocksAfter []string,
	file codebase.File,
	replacementFileContents string,
	alert *alerts.Alert,
) ([]editcommands.EditCommand, error) {
	result := []editcommands.EditCommand{}
	minLine := codebase.LineNumber(-1)

	for i := 0; i < len(splitBlocksBefore); i++ {
		newEdits, err := applyReplacementBlock(
			ctx,
			splitBlocksBefore[i],
			splitBlocksAfter[i],
			replacementFileContents,
			file,
			alert,
			minLine,
		)
		if err != nil {
			return nil, err
		}
		result = append(result, newEdits...)
		for _, edit := range newEdits {
			// set minLine to be the max starting line of the edits
			if minLine < edit.FirstLine()+1 {
				minLine = edit.FirstLine() + 1
			}
		}
	}

	return result, nil
}

/**
 * Splits a block that contain code with line numbers into blocks of consecutive lines.
 *
 * E.g. for the code
 * ```
 * 1: some code
 * 2: some more code
 * 5: other code
 * ```
 *
 * The result will be ["1: some code\n2: some more code", "5: other code"]
 */
func splitNonConsecutiveLines(block string) ([]string, error) {
	lines := strings.Split(block, "\n")
	result := []string{}
	currentBlock := ""
	previousLineNumber := 0

	for i, line := range lines {
		match := snippets.InitialLineNumberRegex.FindString(line)
		if match == "" {
			// if any line without a line number is found, return the original block.
			return []string{block}, nil
		}

		lineNumber, err := strconv.Atoi(strings.TrimSuffix(strings.TrimSpace(match), ":"))
		if err != nil {
			return nil, err
		}

		// Check if current line is consecutive.
		if lineNumber == previousLineNumber+1 || i == 0 {
			if currentBlock != "" {
				currentBlock += "\n"
			}
			currentBlock += line
		} else {
			// Not consecutive, push the current block to result and start a new one.
			result = append(result, currentBlock)
			currentBlock = line
		}
		previousLineNumber = lineNumber
	}

	// Don't forget to add the last block.
	if currentBlock != "" {
		result = append(result, currentBlock)
	}

	return result, nil
}

func removeLineNumbers(block string) string {
	return snippets.LineNumberRegex.ReplaceAllString(block, "")
}

/** A block of text matched from the `original lines:` of a replacement block. */
type BlockMatch struct {
	/** The line (1-indexed) in the file where the match starts. */
	start codebase.LineNumber
	/** The line (1-indexed) in the file where the match ends. */
	end codebase.LineNumber
	/** The corresponding `replacement lines` from the block, which have been adjusted based on the normalizations applied in the `original lines`. */
	afterBlock string
	/** The normalization round used to find the match (lower is less normalization). */
	round int
}

// Start returns the startingline (1-indexed) of the matched block.
func (b *BlockMatch) Start() codebase.LineNumber {
	return b.start
}

// End returns the ending line (1-indexed) of the matched block.
func (b *BlockMatch) End() codebase.LineNumber {
	return b.end
}

// AfterBlock returns the replacement lines corresponding to this match after normalization.
func (b *BlockMatch) AfterBlock() string {
	return b.afterBlock
}

// Round returns the normalization round used to locate the match.
func (b *BlockMatch) Round() int {
	return b.round
}

var getIndentationRegex = regexp.MustCompile("^[ \t]*")

func getIndentation(text string) string {
	re := getIndentationRegex
	found := re.FindString(text)
	if found == "" {
		return ""
	} else {
		return string(found)
	}
}

/**
 * Finds where in `fileContents` the block of text `beforeBlock` is located.
 * A search is done in multiple rounds, where each round does a different normalization of the text.
 * E.g. the indentation might be different between `beforeBlock` and `fileContents` if `beforeBlock` is left-aligned, but we
 * can still find a match if we map the indentations in `block` to the indentations in `fileContents`.
 *
 * The normalizations done to `beforeBlock` are mirrored to `afterBlock`, and returned as part of the result (in `.afterBlock`).
 * That way the caller can use the result to replace the block in `fileContents` with `afterBlock`, and the indentation
 * will fit to the surrounding code.
 *
 * The normalization rounds are as follows:
 * - round 0: no normalization
 * - round 1: normalize indentation by creating a mapping of indentation from `block` to `fileContents`
 * - round 2: normalize all whitespace
 * - round 3: remove all whitespace
 * - round 4: remove empty lines
 * - round 5: + remove all semicolons
 * - round 6: + handle missing prefix / suffix on first / last line respectively
 * - round 7: + ignore first line of original-lines/replace-lines if identical.
 * - round 8: + ignore last line of original-lines/replace-lines if identical.
 * - round 9: + ignore first/last line of original-lines/replace-lines if identical.
 * - round 10: + completely ignore consistency of indentation mapping
 */
func FindBlockMatch(
	beforeBlock string,
	fileContents string,
	afterBlock string,
	shownLines []codebase.LineNumber,
	roundOptional ...int,
) *BlockMatch {
	round := 0
	if len(roundOptional) > 0 {
		round = roundOptional[0]
	}

	if snippets.InitialLineNumberRegex.MatchString(beforeBlock) {
		// recursive with blocks without line numbers
		match := FindBlockMatch(
			removeLineNumbers(beforeBlock),
			fileContents,
			removeLineNumbers(afterBlock),
			shownLines,
			round)
		if match != nil {
			return match
		}
	}

	originalBeforeBlock := beforeBlock
	originalAfterBlock := afterBlock

	// round 7 and later: remove some lines from before/after block if identical
	if round >= 7 {
		beforeBlockLines := strings.Split(beforeBlock, "\n")
		afterBlockLines := strings.Split(afterBlock, "\n")
		// round 7, or 9 and later: remove first line of original-lines/replace-lines if identical.
		if round != 8 && beforeBlockLines[0] == afterBlockLines[0] {
			beforeBlockLines = beforeBlockLines[1:]
			afterBlockLines = afterBlockLines[1:]
		}
		// round 8 or later: remove last line of original-lines/replacement-lines if identical.
		if round >= 8 &&
			len(beforeBlockLines) > 0 && len(afterBlockLines) > 0 &&
			beforeBlockLines[len(beforeBlockLines)-1] == afterBlockLines[len(afterBlockLines)-1] {
			beforeBlockLines = beforeBlockLines[:len(beforeBlockLines)-1]
			afterBlockLines = afterBlockLines[:len(afterBlockLines)-1]
		}
		beforeBlock = strings.Join(beforeBlockLines, "\n")
		afterBlock = strings.Join(afterBlockLines, "\n")
		if strings.TrimSpace(beforeBlock) == "" {
			return nil
		}
	}

	fileLines := strings.Split(fileContents, "\n")
	beforeBlockLines := utils.Filter(strings.Split(beforeBlock, "\n"),
		func(line string) bool {
			// round 4: remove empty lines. Earlier rounds we keep all lines.
			return round < 4 || strings.TrimSpace(line) != ""
		})

	// round 4: remove leading/trailing empty lines
	// we have to remove leading/trailing lines from afterBlock, otherwise it clashes with the empty line removal from 'beforeBlockLines'.
	if round >= 4 {
		afterBlockLines := strings.Split(afterBlock, "\n")
		for len(afterBlockLines) > 0 && strings.TrimSpace(afterBlockLines[0]) == "" {
			if len(afterBlockLines) > 1 {
				afterBlockLines = afterBlockLines[1:]
			} else {
				afterBlockLines = []string{}
			}
		}
		for len(afterBlockLines) > 0 && strings.TrimSpace(afterBlockLines[len(afterBlockLines)-1]) == "" {
			if len(afterBlockLines) > 1 {
				afterBlockLines = afterBlockLines[:len(afterBlockLines)-1]
			} else {
				afterBlockLines = []string{}
			}
		}
		afterBlock = strings.Join(afterBlockLines, "\n")
	}

	// saving if the beforeBlock is missing a prefix/suffix to match some lines in the file.
	missingPrefix := ""
	missingSuffix := ""

outer:
	for _, fileLineIndex := range shownLines {
		fileLineIndex = fileLineIndex - 1 // 1-indexed to 0-indexed
		skippedLines := 0
		indentationMapping := map[string]string{}

		// try to find a match for all the lines in the beforeBlock
		for blockLineIndex := 0; blockLineIndex < len(beforeBlockLines)+skippedLines; blockLineIndex++ {
			beforeBlockLine := strings.TrimSpace(beforeBlockLines[blockLineIndex-skippedLines])
			if len(fileLines) <= int(fileLineIndex)+blockLineIndex {
				// not enough lines left in file, skip to next
				continue outer
			}
			fileLine := strings.TrimSpace(fileLines[int(fileLineIndex)+blockLineIndex])

			if fileLine == "" && beforeBlockLine == "" {
				// empty line in both, continue to next line
				continue
			}

			// round 4: remove empty lines
			if round >= 4 && fileLine == "" && blockLineIndex != 0 {
				// empty line in file, and we're not in the top of the original lines, skip to next
				skippedLines++
				continue
			}

			if round == 0 && beforeBlockLine != fileLine {
				// no normalization, not exact lines, skip
				continue outer
			}

			// round 1: normalize indentation
			beforeBlockIndent := getIndentation(
				beforeBlockLines[blockLineIndex-skippedLines],
			)
			fileLineIndent := getIndentation(
				fileLines[int(fileLineIndex)+blockLineIndex],
			)

			if beforeBlockIndent != fileLineIndent {
				indentation, found := indentationMapping[beforeBlockIndent]
				if found && indentation != fileLineIndent {
					if round <= 9 {
						// round 1-9: indentation mapping must be consistent
						continue outer
					}
					// round 10: potential inconsistent indentation mapping
				}
				indentationMapping[beforeBlockIndent] = fileLineIndent
			}

			// round 6: handle missing prefix / suffix on first / last line respectively
			// this happens before some other normalization, so they don't impact the output
			if round >= 6 {
				// first line, check if we need to add missing prefix
				if blockLineIndex == 0 &&
					strings.HasSuffix(fileLine, beforeBlockLine) &&
					fileLine != beforeBlockLine {
					missingPrefix =
						fileLineIndent + fileLine[:len(fileLine)-len(beforeBlockLine)] // a spurious indentation is added, but that's ok
					beforeBlockLine = fileLine // so we don't skip the line
				}
				// last line, check if we need to add missing suffix
				if blockLineIndex == len(beforeBlockLines)+skippedLines-1 &&
					strings.HasPrefix(fileLine, beforeBlockLine) &&
					fileLine != beforeBlockLine {
					missingSuffix = fileLine[len(beforeBlockLine):]
					beforeBlockLine = fileLine // so we don't skip the line
				}
			}

			// round 2: normalize all whitespace
			if round >= 2 {
				blockOfWhitespaceRegex := regexp.MustCompile(`\s+`)
				beforeBlockLine = blockOfWhitespaceRegex.ReplaceAllString(beforeBlockLine, " ")
				fileLine = blockOfWhitespaceRegex.ReplaceAllString(fileLine, " ")
			}

			// round 3: remove all whitespace
			if round >= 3 {
				singleWhitespaceRegex := regexp.MustCompile(`\s`)
				beforeBlockLine = singleWhitespaceRegex.ReplaceAllString(beforeBlockLine, "")
				fileLine = singleWhitespaceRegex.ReplaceAllString(fileLine, "")
			}

			// round 5: remove all semicolons
			if round >= 5 {
				beforeBlockLine = strings.ReplaceAll(beforeBlockLine, ";", "")
				fileLine = strings.ReplaceAll(fileLine, ";", "")
			}

			// check that the lines match (minus indentation, and other normalization)
			if beforeBlockLine != fileLine {
				// no match, skip
				continue outer
			}

			// match, continue to next line
		}

		// all lines matched
		return &BlockMatch{
			start:      1 + fileLineIndex,
			end:        codebase.LineNumber(int(fileLineIndex) + len(beforeBlockLines) + skippedLines),
			afterBlock: missingPrefix + applyIndentationMapping(afterBlock, indentationMapping) + missingSuffix,
			round:      round,
		}
	}
	// we can try again, with a broader set of normalizations
	if round < 10 {
		beforeBlock = originalBeforeBlock
		afterBlock = originalAfterBlock
		return FindBlockMatch(beforeBlock, fileContents, afterBlock, shownLines, round+1)
	}
	return nil
}

// FindBestBlockMatch finds the best matching block and is a utility function for applyReplacementBlock to use
func FindBestBlockMatch(
	beforeBlock string,
	fileContents string,
	afterBlock string,
	shownLines []codebase.LineNumber,
	file codebase.File,
) (*BlockMatch, error) {
	matches := []BlockMatch{}

	// Find all possible matches
	for len(shownLines) > 0 {
		match := FindBlockMatch(
			beforeBlock,
			fileContents,
			afterBlock,
			shownLines,
		)
		if match == nil {
			break
		}
		matches = append(matches, *match)
		shownLines = utils.Filter(shownLines, func(line codebase.LineNumber) bool {
			return line > match.start
		})
	}

	if len(matches) == 0 {
		return nil, autofix.NewBlockMismatchError(
			"Failed to find original lines in file",
			errors.New("no matches found"),
			file.Path)
	}

	// If we have a line number to differentiate, use that to find the match closest to the line number
	lineNumberMatch := snippets.InitialLineNumberRegex.FindString(beforeBlock)
	if lineNumberMatch != "" {
		firstLine, err := strconv.Atoi(strings.TrimSuffix(strings.TrimSpace(lineNumberMatch), ":"))
		if err != nil {
			return nil, autofix.NewParsingError(
				"Failed to parse line number in file: "+lineNumberMatch,
				nil)
		}

		type BlockMatchWithDistance struct {
			match    BlockMatch
			distance int
		}
		closestMatches := []BlockMatchWithDistance{}
		for _, match := range matches {
			closestMatches = append(closestMatches, BlockMatchWithDistance{
				match:    match,
				distance: abs(int(match.start) - firstLine),
			})
		}

		sort.SliceStable(closestMatches, func(i, j int) bool {
			return closestMatches[i].distance < closestMatches[j].distance
		})
		closestDistance := closestMatches[0].distance

		// Keep only matches with the closest distance
		matches = []BlockMatch{}
		for _, matchWithDistance := range closestMatches {
			if matchWithDistance.distance == closestDistance {
				matches = append(matches, matchWithDistance.match)
			}
		}
	}

	// Select the match using the least rounds of normalization
	minRoundsMatch := matches[0]
	for _, match := range matches {
		if match.round < minRoundsMatch.round {
			minRoundsMatch = match
		}
	}

	matches = utils.Filter(matches, func(match BlockMatch) bool {
		return match.round == minRoundsMatch.round
	})

	if len(matches) > 1 {
		return nil, autofix.NewBadModelOutputError(
			"Multiple matches for the original lines",
			nil)
	}

	return &matches[0], nil
}

func applyIndentationMapping(
	block string,
	indentationMapping map[string]string,
) string {
	blockLines := strings.Split(block, "\n")

	// first, we generalise the indentation mapping: for any indentation t that is
	// mapped to indentation s, we look for all longer indentations t + t' that
	// are not yet mapped, and map them to s + t'

	// all indentations in the block that are not mapped yet
	unmappedBlockIndents := map[string]bool{}
	for _, line := range blockLines {
		indentation := getIndentation(line)
		_, isMapped := indentationMapping[indentation]
		if !isMapped {
			unmappedBlockIndents[indentation] = true
		}
		unmappedBlockIndents[indentation] = true
	}

	// all indentations that are already mapped, sorted by decreasing length
	indents := []string{}
	for indentation := range indentationMapping {
		indents = append(indents, indentation)
	}
	sort.SliceStable(indents, func(i, j int) bool {
		return len(indents[i]) > len(indents[j])
	})

	for _, indent := range indents {
		mappedIndent := indentationMapping[indent]
		for otherIndent := range unmappedBlockIndents {
			if strings.HasPrefix(otherIndent, indent) {
				additionalIndent := strings.TrimPrefix(otherIndent, indent)
				mappedOtherIndent := mappedIndent + additionalIndent
				indentationMapping[otherIndent] = mappedOtherIndent
				unmappedBlockIndents[otherIndent] = false
			}
		}
	}

	// now apply the indentation mapping
	for i, line := range blockLines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		indent := getIndentation(line)
		if (indentationMapping[indent]) != "" {
			blockLines[i] = indentationMapping[indent] + strings.TrimPrefix(line, indent)
		}
	}

	return strings.Join(blockLines, "\n")
}

// fixUtils.go

/**
 * Normalizes a file name, given a list of files that the model has seen.
 */
/**
 * Normalizes a file name, given a list of files that the model has seen.
 */
func normalizeFileName(ctx context.Context, fileName string, seenFiles []string, alert *alerts.Alert) (string, error) {
	logger := enhancedctx.Logger(ctx)
	fileName = utils.NormalizeFilePathForPlatform(fileName)

	// Direct match
	if utils.Contains(seenFiles, fileName) {
		return fileName, nil
	}

	// Basename match
	if matched := matchByBasename(fileName, seenFiles); matched != nil {
		return *matched, nil
	}

	// Dependencies file
	if alert.Language != "" && isDependenciesFile(fileName, alert.Language) {
		logger.Warn("Ignoring edits for dependencies file", kvp.String("gh.autofix.dependencies_file_with_ignored_edits", fileName))
		return "", nil
	}

	// Only one file shown, assume it's the intended file
	if len(seenFiles) == 1 {
		logger.Warn("Assuming the only file shown is edited, instead of the specified file.",
			kvp.String("gh.autofix.only_file_shown", seenFiles[0]),
			kvp.String("gh.autofix.specified_file", fileName),
		)
		return seenFiles[0], nil
	}

	// Ambiguous or not found
	return "", autofix.NewFileNotFoundError("File not shown to model", nil, fileName)
}

// If `file` does not have a dirname, returns the first candidate in `candidates`
// that has the same basename as `file`. Otherwise, returns `nil`.
func matchByBasename(file string, candidates []string) *string {
	basename := filepath.Base(file)
	if basename != file {
		return nil
	}

	candidate, found := utils.FindFirst(candidates, func(c string) bool { return filepath.Base(c) == basename })
	if found {
		return &candidate
	} else {
		return nil
	}
}

// Returns true if the given file may be relevant for dependency management.
func isDependenciesFile(file string, language utils.Language) bool {
	patterns := utils.LanguageDependencyFiles[language]
	if patterns == nil {
		return false
	}

	baseName := filepath.Base(file)

	for _, pattern := range patterns {
		if matched, _ := filepath.Match(pattern, baseName); matched {
			return true
		}
	}
	return false
}
