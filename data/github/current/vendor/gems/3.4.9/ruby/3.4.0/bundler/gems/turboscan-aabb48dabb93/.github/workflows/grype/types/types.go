package types

import (
	"encoding/json"

	"github.com/pkg/errors"
)

type GrypeArtifact struct {
	Name string `json:"name"`
}

type GrypeFix struct {
	State    string   `json:"state"`
	Versions []string `json:"versions"`
}

type GrypeVulnerability struct {
	ID          string   `json:"id"`
	Severity    string   `json:"severity"`
	Description string   `json:"description"`
	URLs        []string `json:"urls"`
	Fix         GrypeFix `json:"fix"`
}

type GrypeMatch struct {
	Vulnerability GrypeVulnerability `json:"vulnerability"`
	Artifact      GrypeArtifact      `json:"artifact"`
}

type GrypeReport struct {
	Matches []GrypeMatch `json:"matches"`
}

type GrypeMatchWithAffectedVersions struct {
	Match                      GrypeMatch
	AffectedEnterpriseVersions []string
}

func ParseGrypeReport(data []byte) (*GrypeReport, error) {
	var report GrypeReport
	err := json.Unmarshal(data, &report)
	if err != nil {
		return nil, errors.Wrap(err, "Unable to parse Grype matches.")
	}
	return &report, nil
}

func GrypeMatchesByID(matches []GrypeMatch) map[string]GrypeMatch {
	result := make(map[string]GrypeMatch)
	for _, match := range matches {
		result[match.Vulnerability.ID] = match
	}
	return result
}

type EnterpriseRelease struct {
	End string `json:"end"`
}
