package queryannotations

import (
	"fmt"
	"net/url"
	"strings"

	"github.com/github/go-queryannotations/annotation"
)

type SQLCommenterFormatter struct {
}

// Name implements Formatter.
func (s *SQLCommenterFormatter) Name() string {
	return "sqlcommenter"
}

// EstimateSize implements Formatter.
func (s *SQLCommenterFormatter) Estimate(components []*annotation.Annotation) int {
	var size int

	for _, c := range components {
		keySize := len(c.Key)
		valueSize := len(c.Value) + 2 // 2 for the quotes

		size = size + keySize + valueSize + 1 // 1 for the separator
	}

	return size
}

// WriteComponent implements Formatter.
func (s *SQLCommenterFormatter) WriteComponent(sb *strings.Builder, c *annotation.Annotation) {
	sb.WriteString(url.QueryEscape(c.Key))
	sb.WriteString("=")
	sb.WriteString("'")
	sb.WriteString(url.QueryEscape(c.Value))
	sb.WriteString("'")
}

// ParseComponent implements Formatter.
func (s *SQLCommenterFormatter) ParseComponent(c string) (*annotation.Annotation, error) {
	kv := strings.SplitN(c, "=", 2)
	if len(kv) == 2 {
		escapedValue := kv[1][1 : len(kv[1])-1] // Remove the quotes
		value, err := url.QueryUnescape(escapedValue)
		if err != nil {
			return nil, fmt.Errorf("unescaping value %q: %w", kv[1], err)
		}

		return &annotation.Annotation{Key: kv[0], Value: value}, nil
	}

	return nil, nil
}

var _ Formatter = (*SQLCommenterFormatter)(nil)
