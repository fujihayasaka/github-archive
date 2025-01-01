package ts

type ProcessErrorID uint64

// A ProcessError represents an error logged during processing of a delivery or analysis
type ProcessError struct {
	BaseModel
	ID           ProcessErrorID
	RepositoryID RepositoryEID
	AnalysisID   *AnalysisID
	ErrorType    ProcessErrorType
	SarifURI     string
	SarifID      SarifID
	Message      string

	// Associations
	Analysis *Analysis
}

func (e *ProcessError) Error() string {
	return e.Message
}

func newProcessError(errorType ProcessErrorType,
	repo RepositoryEID, sarifID SarifID, analysis *Analysis, sarifURI *string, message string) *ProcessError {
	pe := &ProcessError{
		ErrorType:    errorType,
		RepositoryID: repo,
		Message:      message,
		SarifID:      sarifID,
	}
	if analysis != nil {
		pe.Analysis = analysis
		pe.AnalysisID = &analysis.ID
	}
	if sarifURI != nil {
		pe.SarifURI = *sarifURI
	}
	return pe
}

// NewUnrecoverableAnalysisError constructs an instance of ProcessError with error type UnrecoverableAnalysis
// sarifIDs are not available when these errors are constructed, but are added before they are saved
func NewUnrecoverableAnalysisError(repo RepositoryEID, analysis *Analysis, message string) *ProcessError {
	return newProcessError(ProcessErrorTypeUnrecoverableAnalysis,
		repo, "", analysis, nil, message)
}

// NewUnsuccessfulAnalysisError constructs an instance of ProcessError with error type UnsuccessfulAnalysis
func NewUnsuccessfulAnalysisError(repo RepositoryEID, analysis *Analysis, message string) *ProcessError {
	return newProcessError(ProcessErrorTypeUnsuccessfulAnalysis,
		repo, "", analysis, nil, message)
}

// NewUnrecoverableDeliveryError constructs an instance of ProcessError with error type UnrecoverableDelivery
func NewUnrecoverableDeliveryError(repo RepositoryEID, sarifID SarifID, message string) *ProcessError {
	return newProcessError(ProcessErrorTypeUnrecoverableDelivery, repo, sarifID, nil, nil, message)
}

// ProcessErrorType describes the possible types of error that can
// occur during processing.
type ProcessErrorType uint8

// If adding new constants here, be sure to update String() and
// isValid() functions below
const (
	ProcessErrorTypeUnknown               ProcessErrorType = 0
	ProcessErrorTypeUnrecoverableResult   ProcessErrorType = 10 // No longer used
	ProcessErrorTypeUnrecoverableRun      ProcessErrorType = 20 // No longer used.
	ProcessErrorTypeUnrecoverableAnalysis ProcessErrorType = 30
	ProcessErrorTypeAnalysisOutOfOrder    ProcessErrorType = 40 // No longer used.
	ProcessErrorTypeUnrecoverableDelivery ProcessErrorType = 50
	ProcessErrorTypeUnsuccessfulAnalysis  ProcessErrorType = 60
)

func (t ProcessErrorType) String() string {
	switch t {
	case ProcessErrorTypeUnknown:
		return "Unknown"
	case ProcessErrorTypeUnrecoverableResult:
		return "Unrecoverable result"
	case ProcessErrorTypeUnrecoverableRun:
		return "Unrecoverable run"
	case ProcessErrorTypeUnrecoverableAnalysis:
		return "Unrecoverable analysis"
	case ProcessErrorTypeAnalysisOutOfOrder:
		return "Analysis out of order"
	case ProcessErrorTypeUnrecoverableDelivery:
		return "Unrecoverable delivery"
	case ProcessErrorTypeUnsuccessfulAnalysis:
		return "Unsuccessful analysis"
	default:
		panic("Invalid ProcessErrorType value")
	}
}

func (t ProcessErrorType) IsValid() bool {
	switch t {
	case
		ProcessErrorTypeUnknown,
		ProcessErrorTypeUnrecoverableResult,
		ProcessErrorTypeUnrecoverableRun,
		ProcessErrorTypeUnrecoverableAnalysis,
		ProcessErrorTypeAnalysisOutOfOrder,
		ProcessErrorTypeUnrecoverableDelivery,
		ProcessErrorTypeUnsuccessfulAnalysis:
		return true
	default:
		return false
	}
}
