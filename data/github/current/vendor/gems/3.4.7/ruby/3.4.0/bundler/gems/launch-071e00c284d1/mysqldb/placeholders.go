package mysqldb

import "strings"

func Placeholders(n int) string {
	// https://stackoverflow.com/a/20275714/29691
	if n > 0 {
		return "?" + strings.Repeat(",?", n-1)
	}
	return ""
}
