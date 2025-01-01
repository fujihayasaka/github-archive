package cocofix

import (
	"bytes"
	"regexp"
)

// sanitizeJsonString removes the 'diff' field from the response to avoid logging sensitive data
func sanitizeJsonString(s string) string {
	regex := regexp.MustCompile(`"diff":\s*"(?:\\"|[^"])*"`)
	sJson := regex.ReplaceAllString(s, `"diff": "REDACTED"`)
	return sJson
}

// truncateBuffers truncate the buffers to the total limit allowed
func truncateBuffers(totalLimit int, buffers ...*bytes.Buffer) {
	totalBytes := 0
	for _, b := range buffers {
		totalBytes += b.Len()
	}

	if totalBytes > totalLimit {
		totalBytes = totalLimit
	}

	for _, b := range buffers {
		if b.Len() > totalBytes {
			b.Truncate(totalBytes)
		}
		totalBytes -= b.Len()
	}
}
