package common

import (
	"fmt"
	"strings"
)

// TruncateString truncates a string limited by the max characters defined.
// Appends ... and the last three characters of the string if maxChars is greater than 6
//
// Example TruncateString("123456789123456789", 9)
// Returns "123...789"
// Example TruncateString("123456789123456789", 3)
// Returns "123"
func TruncateString(str string, maxChars int) string {
	if len(str) <= maxChars {
		return str
	}

	// if we can't afford the trailing chars (...abc)
	// just trim the string down
	if maxChars <= 6 {
		return str[0:maxChars]
	}

	newLen := maxChars - 6
	return str[0:newLen] + "..." + str[len(str)-3:]
}

// Int64sToString takes []int64 and a delimiter to convert it into a string
func Int64sToString(arr []int64, delimiter string) string {
	var response strings.Builder
	for i, id := range arr {
		if i != 0 {
			response.WriteString(delimiter)
		}
		response.WriteString(fmt.Sprint(id))
	}
	return response.String()
}
