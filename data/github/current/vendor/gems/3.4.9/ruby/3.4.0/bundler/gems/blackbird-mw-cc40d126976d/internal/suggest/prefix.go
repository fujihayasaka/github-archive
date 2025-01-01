package suggest

import (
	"sort"
	"strings"
)

// Takes a lowercase sorted list of strings, returns the sublist which matches
// the needle as a prefix
func suggestPrefix(haystack []string, needle string) []string {
	start := sort.SearchStrings(haystack, strings.ToLower(needle))

	var end int
	for end = start; end < len(haystack); end++ {
		if !strings.HasPrefix(haystack[end], needle) {
			break
		}
	}

	return haystack[start:end]
}
