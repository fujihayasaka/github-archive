package ts

type AnalysisQuerySuiteID uint64

type AnalysisQuerySuiteType uint8

const (
	AnalysisQuerySuiteTypeUnknown AnalysisQuerySuiteType = iota
	AnalysisQuerySuiteTypeLocalQuery
	AnalysisQuerySuiteTypeBuiltinSuite
	AnalysisQuerySuiteTypeExternalRepo
)

type AnalysisQuerySuite struct {
	ID           AnalysisQuerySuiteID
	AnalysisID   AnalysisID
	RepositoryID RepositoryEID
	Type         AnalysisQuerySuiteType
	Uses         string
}

func (t AnalysisQuerySuiteType) String() string {
	switch t {
	case AnalysisQuerySuiteTypeLocalQuery:
		return "localQuery"
	case AnalysisQuerySuiteTypeBuiltinSuite:
		return "builtinSuite"
	case AnalysisQuerySuiteTypeExternalRepo:
		return "externalRepo"
	case AnalysisQuerySuiteTypeUnknown:
		return "unknown"
	}
	return "unknown"
}
