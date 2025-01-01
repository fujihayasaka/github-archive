package ts

import (
	"github.com/SamuelTissot/sqltime"
)

// CodeqlSchedule contains the schedule information for managed analyses
type CodeqlSchedule struct {
	BaseModel
	ID CodeqlScheduleID

	RepositoryID RepositoryEID

	NextRunAt sqltime.Time
}

// CodeqlScheduleID represents the database ID for a CodeqlSchedule entry
type CodeqlScheduleID uint64
