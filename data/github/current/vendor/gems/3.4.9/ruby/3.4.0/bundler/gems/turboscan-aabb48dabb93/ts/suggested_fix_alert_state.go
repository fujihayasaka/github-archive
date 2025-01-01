package ts

type SuggestedFixAlertState string

const (
	SuggestedFixAlertStateApplied          SuggestedFixAlertState = "applied"
	SuggestedFixAlertStateError            SuggestedFixAlertState = "error"
	SuggestedFixAlertStateInvalid          SuggestedFixAlertState = "invalid"
	SuggestedFixAlertStateRuleNotSupported SuggestedFixAlertState = "rule_not_supported"
	SuggestedFixAlertStatePending          SuggestedFixAlertState = "pending"
	SuggestedFixAlertStateValid            SuggestedFixAlertState = "valid"
	SuggestedFixAlertStateValidMissingDep  SuggestedFixAlertState = "valid_missing_dep"
)

// SuggestedFixAlertStateValidStates is a list of states that are considered valid.
var SuggestedFixAlertStateValidStates = []SuggestedFixAlertState{
	SuggestedFixAlertStateValid, SuggestedFixAlertStateValidMissingDep,
}

func (s SuggestedFixAlertState) String() string {
	switch s {
	case SuggestedFixAlertStateApplied:
		return "applied"
	case SuggestedFixAlertStateError:
		return "error"
	case SuggestedFixAlertStateInvalid:
		return "invalid"
	case SuggestedFixAlertStateRuleNotSupported:
		return "rule-not-supported"
	case SuggestedFixAlertStatePending:
		return "pending"
	case SuggestedFixAlertStateValid:
		return "valid"
	case SuggestedFixAlertStateValidMissingDep:
		return "valid-missing-dep"
	default:
		return "unknown"
	}
}

// DBString returns the string representation of the SuggestedFixAlertState for the database and ES.
func (s SuggestedFixAlertState) DBString() string {
	return string(s)
}

func (s *SuggestedFixAlertState) IsPending() bool {
	return *s == SuggestedFixAlertStatePending
}

func (s *SuggestedFixAlertState) IsError() bool {
	return *s == SuggestedFixAlertStateError
}

func (s *SuggestedFixAlertState) IsNotSupported() bool {
	return *s == SuggestedFixAlertStateRuleNotSupported
}

func (s *SuggestedFixAlertState) IsValid() bool {
	return *s == SuggestedFixAlertStateValid
}
