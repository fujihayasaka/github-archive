package ts

type AnalysisExtractedFilesMessages struct {
	ID           uint64
	RepositoryID RepositoryEID
	AnalysisID   AnalysisID
	Path         string
	Message      string
	BaseModel
}
