package ts

import (
	"github.com/pkg/errors"
)

var (
	ErrSuggestedFixAlertNotFound = errors.New("SuggestedFixAlert not found")
)

type SuggestedFixID uint64

type SuggestedFix struct {
	BaseModel
	ID                 SuggestedFixID `verify:"ignore"`
	RepositoryID       RepositoryEID
	AiVersion          string
	AiModel            string
	Description        string
	DependencyMetadata SuggestedFixDependencyMetadata

	// Associations
	Files  []*SuggestedFixFile
	Alerts []*SuggestedFixAlert
}
