package ts

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/pkg/errors"
)

type SuggestedFixDependencyMetadata []SuggestedFixDependency

func (v *SuggestedFixDependencyMetadata) Scan(src interface{}) error {
	doc, ok := src.([]byte)
	if !ok {
		return errors.New("unknown document type")
	}
	return errors.Wrap(json.Unmarshal(doc, v), "failed to Scan SuggestedFixDependencyMetadata")
}

func (v SuggestedFixDependencyMetadata) Value() (driver.Value, error) {
	data, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	return string(data), err
}

type SuggestedFixDependency struct {
	Name        string
	Version     string
	Description string
	Url         string
	Ecosystem   string
	IsMalicious bool
	Advisories  []SuggestedFixAdvisory
}

type SuggestedFixAdvisorySeverity string

const (
	SuggestedFixAdvisorySeverity_UNKNOWN  SuggestedFixAdvisorySeverity = "unknown"
	SuggestedFixAdvisorySeverity_LOW      SuggestedFixAdvisorySeverity = "low"
	SuggestedFixAdvisorySeverity_MEDIUM   SuggestedFixAdvisorySeverity = "medium"
	SuggestedFixAdvisorySeverity_HIGH     SuggestedFixAdvisorySeverity = "high"
	SuggestedFixAdvisorySeverity_CRITICAL SuggestedFixAdvisorySeverity = "critical"
)

type SuggestedFixAdvisory struct {
	Id          string
	HtmlUrl     string
	Summmary    string
	Description string
	Severity    SuggestedFixAdvisorySeverity
}
