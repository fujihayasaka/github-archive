package ts

type AlertLinkID uint64

type AlertLink struct {
	BaseModel
	ID             AlertLinkID `verify:"ignore"`
	RepositoryID   RepositoryEID
	LogicalAlertID LogicalAlertID
	Ref            []byte
	PullRequestID  PullRequestEID

	// AlertNumber is not stored in the database
	AlertNumber uint32 `gorm:"-" verify:"ignore"`
}

type AlertLinkWithoutID struct {
	RepositoryID  RepositoryEID
	Ref           []byte
	PullRequestID PullRequestEID
	AlertNumber   uint32 `gorm:"-" verify:"ignore"`
}
