package ts

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/pkg/errors"
)

type AnalysisExtractedFilesID uint64

type ToolStatusFiles map[string]FileSet

func (v *ToolStatusFiles) Scan(src interface{}) error {
	doc, ok := src.([]byte)
	if !ok {
		return errors.New("unknown document type")
	}
	return errors.Wrap(json.Unmarshal(doc, v), "failed to Scan ToolStatusFiles")
}

func (v ToolStatusFiles) Value() (driver.Value, error) {
	data, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	return string(data), err
}

type AnalysisExtractedFiles struct {
	BaseModel
	ID                AnalysisExtractedFilesID
	AnalysisID        AnalysisID
	RepositoryID      RepositoryEID
	FilesExtracted    ToolStatusFiles
	FilesNotExtracted ToolStatusFiles

	Analysis *Analysis
}
