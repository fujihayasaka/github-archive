package ts

// CodeqlRunStatus represents the status of a run
type CodeqlRunStatus uint8

const (
	CodeqlRunStatus_PENDING CodeqlRunStatus = iota
	CodeqlRunStatus_INPROGRESS
	CodeqlRunStatus_COMPLETED
	CodeqlRunStatus_FAILED
	CodeQlRunStatus_CANCELLED
)

func (s CodeqlRunStatus) String() string {
	var state string

	switch s {
	case CodeqlRunStatus_PENDING:
		state = "pending"
	case CodeqlRunStatus_INPROGRESS:
		state = "in-progress"
	case CodeqlRunStatus_COMPLETED:
		state = "completed"
	case CodeqlRunStatus_FAILED:
		state = "failed"
	case CodeQlRunStatus_CANCELLED:
		state = "cancelled"
	}

	return state
}

func (s CodeqlRunStatus) IsFinal() bool {
	return s == CodeqlRunStatus_COMPLETED || s == CodeqlRunStatus_FAILED || s == CodeQlRunStatus_CANCELLED
}
