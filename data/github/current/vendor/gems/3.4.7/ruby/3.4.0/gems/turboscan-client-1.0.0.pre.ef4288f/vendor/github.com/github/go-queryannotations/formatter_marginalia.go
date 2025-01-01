package queryannotations

import (
	"strings"

	"github.com/github/go-queryannotations/annotation"
)

type MarginaliaFormatter struct {
}

// Name implements Formatter.
func (s *MarginaliaFormatter) Name() string {
	return "marginalia"
}

// EstimateSize implements Formatter.
func (m *MarginaliaFormatter) Estimate(components []*annotation.Annotation) int {
	var size int

	for _, c := range components {
		// Include key, value, separator in between ":" and in between pairs ","
		size += len(c.Key) + len(c.Value) + 2
	}

	return size
}

// WriteComponent implements Formatter.
func (m *MarginaliaFormatter) WriteComponent(sb *strings.Builder, c *annotation.Annotation) {
	sb.WriteString(c.Key)
	sb.WriteString(":")
	sb.WriteString(c.Value)
}

// ParseComponent implements Formatter.
func (m *MarginaliaFormatter) ParseComponent(c string) (*annotation.Annotation, error) {
	kv := strings.SplitN(c, ":", 2)
	if len(kv) == 2 {
		return &annotation.Annotation{Key: kv[0], Value: kv[1]}, nil
	}

	return nil, nil
}

var _ Formatter = (*MarginaliaFormatter)(nil)
