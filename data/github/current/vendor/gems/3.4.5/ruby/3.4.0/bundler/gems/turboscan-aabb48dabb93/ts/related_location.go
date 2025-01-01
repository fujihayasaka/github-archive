package ts

type RelatedLocationID uint64

// A RelatedLocation is a location, annotated with a string message, that aids
// in understanding a particular alert. A PhysicalAlert may have multiple
// RelatedLocations associated with it.
// In the case of CodeQL, RelatedLocations are referenced via their
// ReplacementIndex from alert messages. The UI can dereference the relevant
// RelatedLocation and use it to generate an inline link to the referenced
// code location.
type RelatedLocation struct {
	BaseModel
	ID               RelatedLocationID `verify:"ignore"`
	RepositoryID     RepositoryEID
	FilePath         string
	Region           Region `gorm:"EMBEDDED"`
	Message          string
	ReplacementIndex uint32
	PhysicalAlertID  PhysicalAlertID `verify:"ignore"`
}
