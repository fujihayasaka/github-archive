package alephcompat

import (
	"strings"

	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/gitaccess"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

// This code has been ported directly from the Aleph sources.

// DefinitionSymbolDataToLocation converts a Blackbird definition symbol result into an Aleph protobuf Location.
func DefinitionSymbolDataToLocation(doc *pb.GitDocumentMatch, symbol *pb.Symbol) (*pb.AlephLocation, error) {
	return &pb.AlephLocation{
		FirstLine:  IdentLineFromOffsets(doc.Content, symbol.IdentStart, symbol.IdentEnd),
		Path:       doc.Locations[0].Path,
		SymbolKind: symbol.Kind,
		Kind:       symbolKindToString(symbol.Kind),
		Pkg: &pb.AlephPackage{
			RepositoryId: uint64(doc.Locations[0].RepoId),
			CommitOid:    gitaccess.NewObjectIDFromBytes(doc.Locations[0].CommitSha).String(),
		},
		Ident:  IdentRangeFromOffsets(doc.Content, symbol.IdentStart, symbol.IdentEnd),
		Extent: ExtentRangeFromOffsets(doc.Content, symbol.ExtentStart, symbol.ExtentEnd),
	}, nil
}

// ReferenceSymbolDataToLocation converts a Blackbird reference symbol result into an Aleph protobuf Location.
func ReferenceSymbolDataToLocation(doc *pb.GitDocumentMatch, startOffset, endOffset uint32, kind entities.SymbolKind) (*pb.AlephLocation, error) {
	identRange := IdentRangeFromOffsets(doc.Content, startOffset, endOffset)
	return &pb.AlephLocation{
		FirstLine:  IdentLineFromOffsets(doc.Content, startOffset, endOffset),
		Path:       doc.Locations[0].Path,
		SymbolKind: kind,
		Kind:       symbolKindToString(kind),
		Pkg: &pb.AlephPackage{
			RepositoryId: uint64(doc.Locations[0].RepoId),
			CommitOid:    gitaccess.NewObjectIDFromBytes(doc.Locations[0].CommitSha).String(),
		},
		Ident: identRange,
		Extent: &pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      0,
				Character: 0,
			},
			End: &pb.AlephPosition{
				Line:      0,
				Character: 0,
			},
		},
	}, nil
}

// IdentRangeFromOffsets converts the byte offsets for any given Blackbird symbol into an Aleph Range representing
// the symbol's identifier range.
func IdentRangeFromOffsets(source []byte, startOffset, endOffset uint32) *pb.AlephRange {
	// Find the index of the preceding newline before the start of the symbol's identifier.
	lineStartOffset := strings.LastIndex(string(source[:startOffset]), "\n")
	// Add one to represent the index of the first character of the symbol's line.
	lineStartOffset += 1

	// Calculate the ident line number.
	lineNumber := strings.Count(string(source[:startOffset]), "\n") // rows are 0 indexed in aleph

	// Calculate the column position of the start and end of the symbol.
	columnStart := int(startOffset) - lineStartOffset
	columnEnd := int(endOffset) - lineStartOffset

	return &pb.AlephRange{
		Start: &pb.AlephPosition{
			Line:      uint32(lineNumber),
			Character: uint32(columnStart),
		},
		End: &pb.AlephPosition{
			Line:      uint32(lineNumber),
			Character: uint32(columnEnd),
		},
	}
}

// IdentLineFromOffsets converts the byte offsets for any Blackbird symbol into a string representing the
// containing line of the symbol's identifier.
func IdentLineFromOffsets(source []byte, startOffset, endOffset uint32) string {
	// Find the index of the preceding newline before the start of the symbol's identifier.
	lineStartOffset := strings.LastIndex(string(source[:startOffset]), "\n")
	// Add one to represent the index of the first character of the symbol's line.
	lineStartOffset += 1

	// Find the relative offset of the first newline after the symbol's identifier.
	// This offset lets us calculate the symbol line's end offset.
	lineEndRelativeOffset := strings.Index(string(source[startOffset:]), "\n")

	var lineEndOffset int
	if lineEndRelativeOffset == -1 {
		// If the symbol line is the last line of a file, there may not be a trailing newline.
		// The `strings.Index` value for this case is -1, meaning the lineEndOffset is equal to the length of the source.
		lineEndOffset = len(source)
	} else {
		lineEndOffset = int(startOffset) + lineEndRelativeOffset
	}

	// Extract the full line containing the symbol.
	return string(source[lineStartOffset:lineEndOffset])
}

// ExtentRangeFromOffsets converts the byte offsets for a given Blackbird definition symbol into an Aleph Range
// representing the symbol's full definition range.
func ExtentRangeFromOffsets(source []byte, startOffset, endOffset uint32) *pb.AlephRange {
	// Find the index of the preceding newline before the start of the symbol's identifier.
	lineStartOffset := strings.LastIndex(string(source[:startOffset]), "\n")
	// Add one to represent the index of the first character of the symbol's line.
	lineStartOffset += 1

	// Find the offset of the first newline after the symbol's extent end offset.
	lineEndOffset := strings.LastIndex(string(source[:endOffset]), "\n")

	// Calculate the ident line number.
	lineNumber := strings.Count(string(source[:startOffset]), "\n") // rows are 0 indexed in aleph

	// If the symbol's extent ends on the last first line, there may not be a trailing newline.
	// The `strings.Index` value for this case is -1, so we handle this case explicitly.
	var lineEndIndex int
	if lineEndOffset == -1 {
		// If there is no preceding newline before the extent end,
		// then the extent line is the first line of the file.
		lineEndIndex = 0
	} else {
		// If there is a preceding newline before the extent end,
		// then the extent line is the line after the preceding newline.
		// We add one to represent the index of the first character of the extent line.
		lineEndIndex = lineEndOffset + 1
	}

	columnStart := int(startOffset) - lineStartOffset
	columnEnd := int(endOffset) - lineEndIndex

	// Calculate the extent end line number by calculating the number of newlines
	// until the extent end offset.
	endLineNumber := strings.Count(string(source[:endOffset]), "\n") // rows are 0 indexed in aleph

	return &pb.AlephRange{
		Start: &pb.AlephPosition{
			Line:      uint32(lineNumber),
			Character: uint32(columnStart),
		},
		End: &pb.AlephPosition{
			Line:      uint32(endLineNumber),
			Character: uint32(columnEnd),
		},
	}
}

func symbolKindToString(kind entities.SymbolKind) string {
	switch kind {
	case entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF:
		return "function"
	case entities.SymbolKind_SYMBOL_KIND_METHOD_DEF:
		return "method"
	case entities.SymbolKind_SYMBOL_KIND_CLASS_DEF:
		return "class"
	case entities.SymbolKind_SYMBOL_KIND_MODULE_DEF:
		return "module"
	case entities.SymbolKind_SYMBOL_KIND_CALL_REF:
		return "call"
	case entities.SymbolKind_SYMBOL_KIND_TYPE_DEF:
		return "type"
	case entities.SymbolKind_SYMBOL_KIND_INTERFACE_DEF:
		return "interface"
	case entities.SymbolKind_SYMBOL_KIND_IMPLEMENTATION_DEF:
		return "implementation"
	case entities.SymbolKind_SYMBOL_KIND_CONSTANT_DEF:
		return "constant"
	case entities.SymbolKind_SYMBOL_KIND_FIELD_DEF:
		return "field"
	case entities.SymbolKind_SYMBOL_KIND_MACRO_DEF:
		return "macro"
	default:
		return "unknown"
	}
}
