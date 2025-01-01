package errorredaction_test

import (
	"strings"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"

	"github.com/github/turboscan/ts/errorredaction"

	"github.com/stretchr/testify/assert"
)

func TestRedactString(t *testing.T) {
	// Simple redaction case.
	result := errorredaction.RedactString("ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE project_nwo='secret'' at line 1", "secret")
	assert.Equal(t, "ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE project_nwo='[REDACTED]'' at line 1", result)

	// Maybe the string appears multiple times.
	result = errorredaction.RedactString("ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE project_nwo='secret' AND project_name='secret'' at line 1", "secret")
	assert.Equal(t, "ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE project_nwo='[REDACTED]' AND project_name='[REDACTED]'' at line 1", result)

	// Strings shorter than 4 letters should not be redacted to avoid over-redaction.
	result = errorredaction.RedactString("ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE field='tes'' at line 1", "tes")
	assert.Equal(t, "ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE field='tes'' at line 1", result)

	// Prefix matches shorter than 4 letters should not be redacted to avoid over-redaction.
	result = errorredaction.RedactString("ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE field='tes'' at line 1", "test")
	assert.Equal(t, "ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE field='tes'' at line 1", result)

	// Strings 4 letters or longer should be redacted.
	result = errorredaction.RedactString("ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE field='test'' at line 1", "test")
	assert.Equal(t, "ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE field='[REDACTED]'' at line 1", result)

	// Even if the whole string is not present, a prefix should cause a redaction.
	result = errorredaction.RedactString("ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE project_nwo='asuperlongsecret...' at line 1", "asuperlongsecretwithlotsofcharactersthatgetstruncated")
	assert.Equal(t, "ERROR 1064 (42000): You have an error in your SQL syntax near 'WHERE project_nwo='[REDACTED]...' at line 1", result)

	// A suffix should cause a redaction too.
	result = errorredaction.RedactString("ERROR 1064 (42000): You have an error in your SQL syntax near '...thatgetstruncated' AND another_thing' at line 1", "asuperlongsecretwithlotsofcharactersthatgetstruncated")
	assert.Equal(t, "ERROR 1064 (42000): You have an error in your SQL syntax near '...[REDACTED]' AND another_thing' at line 1", result)

	// A match at the very start of the string should be redacted correctly.
	result = errorredaction.RedactString("test this is", "test")
	assert.Equal(t, "[REDACTED] this is", result)

	// A match at the very end of the string should be redacted correctly.
	result = errorredaction.RedactString("this is a test", "test")
	assert.Equal(t, "this is a [REDACTED]", result)

	// A match should be redacted correctly even if it is at the end of another aborted match.
	result = errorredaction.RedactString("ttesttest", "test")
	assert.Equal(t, "t[REDACTED][REDACTED]", result)

	// A match should be redacted correctly even if matching a variable requires backtracking.
	result = errorredaction.RedactString("aaabbbccc", "aabb")
	assert.Equal(t, "a[REDACTED]bccc", result)

	// Strings with things like quotes that get escaped when returned should be correctly redacted.
	result = errorredaction.RedactString(`vttablet: Data too long for column 'message' at row 1 (errno 1406) (sqlstate 22001) (CallerID: turboscan_rw): Sql: "insert into ts_process_errors(message) values (:vtg1)", BindVars: {vtg1: "type:VARCHAR value:\"an invalid URI was provided as a SARIF location: parse \\\"some@really:really/long/location\\\": first path segment in URL cannot contain colon,\""}`, `an invalid URI was provided as a SARIF location: parse "some@really:really/long/location": first path segment in URL cannot contain colon,`)
	assert.Equal(t, `vttablet: Data too long for column 'message' at row 1 (errno 1406) (sqlstate 22001) (CallerID: turboscan_rw): Sql: "insert into ts_process_errors(message) values (:vtg1)", BindVars: {vtg1: "type:VARCHAR value:\"[REDACTED],\""}`, result)
}

func TestErrorRedaction(t *testing.T) {
	db := dbtest.RequireConnection(t)
	db.Callback().Query().Register("redaction_callback", errorredaction.DatabaseRedactionCallback)
	var result ts.Rule

	err := db.Where("SYNTAX ? ERROR", "supersecret").First(&result).Error
	assert.False(t, strings.Contains(err.Error(), "supersecret"))
	assert.True(t, strings.Contains(err.Error(), "[REDACTED]"))

	err = db.Where("SYNTAX ? ERROR", []string{"super", "secret"}).First(&result).Error
	assert.False(t, strings.Contains(err.Error(), "super"))
	assert.False(t, strings.Contains(err.Error(), "secret"))
	assert.True(t, strings.Contains(err.Error(), "[REDACTED]"))
}
