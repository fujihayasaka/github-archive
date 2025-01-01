package ts

import (
	"crypto/sha256"
	"database/sql/driver"
	"encoding/json"
	"sort"

	"github.com/gowebpki/jcs"

	"github.com/pkg/errors"
)

type CodeFlowsDocumentID uint64

// CodeFlowsDocument contains all the code flows for a physical alert, flattened and stored as a JSON document.
type CodeFlowsDocument struct {
	BaseModel
	ID           CodeFlowsDocumentID `verify:"ignore"`
	RepositoryID RepositoryEID
	RawDocument  json.RawMessage `gorm:"column:document" verify:"ignore"`
	Document     CodeFlows       `gorm:"-" verify:"array"`
	DocumentHash []byte
}

func (c *CodeFlowsDocument) BeforeSave() (err error) {
	if c.RawDocument == nil {
		c.RawDocument, err = json.Marshal(c.Document)
		if err != nil {
			return
		}
	}
	if c.DocumentHash == nil {
		c.DocumentHash, err = jsonHash(c.RawDocument)
	}
	return
}

func jsonHash(data json.RawMessage) ([]byte, error) {
	var err error
	// canonicalize document for hash using rfc8785 to ensure that two documents with different formatting
	// have the same hash
	// see also: https://www.rfc-editor.org/rfc/rfc8785
	data, err = jcs.Transform(data)
	if err != nil {
		return nil, errors.Wrap(err, "failed to normalize json document")
	}
	hash := sha256.Sum256(data)
	return hash[:], nil
}

func (c *CodeFlowsDocument) beforeVerify() *CodeFlowsDocument {
	_ = c.BeforeSave()
	return c
}

func (c *CodeFlowsDocument) AfterFind() error {
	return json.Unmarshal(c.RawDocument, &c.Document)
}

type CodeFlows []CodeFlow

// UnmarshalJSON unpacks a CodeFlow from a JSON array.
func (codeFlow *CodeFlow) UnmarshalJSON(b []byte) error {
	// Unpack the individual fields so we can scan them directly into the struct
	var row []json.RawMessage
	if err := json.Unmarshal(b, &row); err != nil {
		return errors.Wrap(err, "failed to unwrap code flows")
	}
	fields := codeFlow.fields()

	for idx, column := range row {
		// unmarshal the json.RawMessage directly into the struct field via the pointer
		if err := json.Unmarshal(column, fields[idx]); err != nil {
			return errors.Wrapf(err, "failed to unmarshal CodeFlow[%d]", idx)
		}
	}

	return nil
}

// MarshalJSON packs a CodeFlow struct into a JSON array.
// We use an array instead of an object to:
//   - save space given that this is a highly populated table
//   - allow us to hash the json document without worrying about key ordering changing between mysql versions
//     affecting the hash
func (codeFlow CodeFlow) MarshalJSON() ([]byte, error) {
	data, err := json.Marshal(codeFlow.fields())
	return data, errors.Wrap(err, "failed to marshal CodeFlow")
}

// Value creates a JSON array from a slice of CodeFlow structs.
func (codeFlows CodeFlows) Value() (driver.Value, error) {
	data, err := json.Marshal(codeFlows)
	return string(data), errors.Wrap(err, "failed to create Value from CodeFlow")
}

// Scan unpacks a JSON array from the database into a slice of CodeFlow structs.
func (codeFlows *CodeFlows) Scan(src interface{}) error {
	doc, ok := src.([]byte)
	if !ok {
		return errors.New("unknown document type")
	}
	return errors.Wrap(json.Unmarshal(doc, codeFlows), "failed to Scan CodeFlow")
}

// CodeFlow contains flattened thread flow location information.
type CodeFlow struct {
	FilePath        string
	Region          Region `gorm:"EMBEDDED"`
	Message         *string
	CodeFlowIndex   uint32
	ThreadFlowIndex uint32
	StepIndex       uint32
}

func (codeFlow *CodeFlow) beforeVerify() *CodeFlow {
	if codeFlow == nil {
		return codeFlow
	}
	out := *codeFlow
	// Codeflow indexes are not serialized consistently when dealing with
	// analyses that have been limited.
	// See https://github.com/github/code-scanning/issues/6787 for details
	out.CodeFlowIndex = 0
	return &out
}

// fields returns an array of pointers to the CodeFlow struct data to read and write the document
// to and from the database as a JSON array.
// The array items are in alphabetical order. Any new items should be added to the end of the array.
func (codeFlow *CodeFlow) fields() []interface{} {
	return []interface{}{
		&codeFlow.CodeFlowIndex,
		&codeFlow.FilePath,
		&codeFlow.Message,
		&codeFlow.Region.EndColumn,
		&codeFlow.Region.EndLine,
		&codeFlow.Region.StartColumn,
		&codeFlow.Region.StartLine,
		&codeFlow.StepIndex,
		&codeFlow.ThreadFlowIndex,
	}
}

func groupCodeFlows(codeFlows CodeFlows, fn func(cf *CodeFlow) uint32) []CodeFlows {
	indexes := make(map[uint32]int)
	output := make([]CodeFlows, 0)

	for _, codeFlow := range codeFlows {
		index := fn(&codeFlow)
		target, ok := indexes[index]
		if !ok {
			// We have not seen this index before. We want to create
			// a new slot to hold this group of entries.
			// Take the next available index:
			target = len(output)
			// Extend output. Target is now the index of the last element.
			output = append(output, nil)
			// Next time we see another item with this index
			// we want to append it to the same group.
			indexes[index] = target
		}
		output[target] = append(output[target], codeFlow)
	}

	return output
}

func GroupByCodeFlowIndex(codeFlows CodeFlows) []CodeFlows {
	return groupCodeFlows(codeFlows, func(cf *CodeFlow) uint32 { return cf.CodeFlowIndex })
}

func GroupByThreadFlowIndex(codeFlows CodeFlows) []CodeFlows {
	return groupCodeFlows(codeFlows, func(cf *CodeFlow) uint32 { return cf.ThreadFlowIndex })
}

// SortCodeFlows puts CodeFlows into the canonical ordering.
func SortCodeFlows(codeFlows CodeFlows) CodeFlows {
	// canonicalize order of items in case loaded thread flow locations are out of order.
	sort.Slice(codeFlows, func(i, j int) bool {
		a := codeFlows[i]
		b := codeFlows[j]
		if a.CodeFlowIndex != b.CodeFlowIndex {
			return a.CodeFlowIndex < b.CodeFlowIndex
		}
		if a.ThreadFlowIndex != b.ThreadFlowIndex {
			return a.ThreadFlowIndex < b.ThreadFlowIndex
		}
		return a.StepIndex < b.StepIndex
	})
	return codeFlows
}
