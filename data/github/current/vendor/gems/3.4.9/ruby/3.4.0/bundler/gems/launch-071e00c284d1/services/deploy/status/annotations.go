package status

import (
	"fmt"

	errs "github.com/pkg/errors"
)

const (
	AnnotationNotice  = "NOTICE"
	AnnotationWarning = "WARNING"
	AnnotationFailure = "FAILURE"
)

func getAnnotationLevelName(level AnnotationLevel) (string, error) {
	switch level {
	case AnnotationLevel_LEVEL_FAILURE:
		return AnnotationFailure, nil
	case AnnotationLevel_LEVEL_WARNING:
		return AnnotationWarning, nil
	case AnnotationLevel_LEVEL_NOTICE:
		return AnnotationNotice, nil
	default:
		return "", errs.Errorf("invalid checksuite annotation level %q", level)
	}
}

func getAnnotationSummary(annotations []*Annotation) string {
	var summary = "There are %d failures, %d warnings, and %d notices."
	var failures, warnings, notices int
	for _, annotation := range annotations {
		switch annotation.GetAnnotationLevel() {
		case AnnotationLevel_LEVEL_FAILURE:
			failures++
		case AnnotationLevel_LEVEL_WARNING:
			warnings++
		case AnnotationLevel_LEVEL_NOTICE:
			notices++
		default:
			// don't care about other levels
			continue
		}
	}
	return fmt.Sprintf(summary, failures, warnings, notices)
}
