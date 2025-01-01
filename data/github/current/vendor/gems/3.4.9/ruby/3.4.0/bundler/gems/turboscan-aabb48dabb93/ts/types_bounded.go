package ts

// Bounded strings of various lengths.
//
// Each type defines a NewStringX function that truncates the string to the
// maximum length. This is useful for ensuring that we don't accidentally
// store a string that is too long in the database.
//
// These types are intentionally unexported, so that we rely on better
// named types.

type string40 string

func newString40(s string) (string40, bool) {
	out, ok := truncatedCopy(s, 40)
	return string40(out), ok
}

func toString40(s string) string40 {
	out, _ := newString40(s)
	return out
}

type string140 string

func newString140(s string) (string140, bool) {
	out, ok := truncatedCopy(s, 140)
	return string140(out), ok
}

func toString140(s string) string140 {
	out, _ := newString140(s)
	return out
}

type string255 string

func newString255(s string) (string255, bool) {
	out, ok := truncatedCopy(s, 255)
	return string255(out), ok
}

func toString255(s string) string255 {
	out, _ := newString255(s)
	return out
}

type string280 string

func newString280(s string) (string280, bool) {
	out, ok := truncatedCopy(s, 280)
	return string280(out), ok
}

func toString280(s string) string280 {
	out, _ := newString280(s)
	return out
}

type string1000 string

func newString1000(s string) (string1000, bool) {
	out, ok := truncatedCopy(s, 1000)
	return string1000(out), ok
}

func toString1000(s string) string1000 {
	out, _ := newString1000(s)
	return out
}

type string1024 string

func newString1024(s string) (string1024, bool) {
	out, ok := truncatedCopy(s, 1024)
	return string1024(out), ok
}

func toString1024(s string) string1024 {
	out, _ := newString1024(s)
	return out
}

// truncatedCopy returns a copy of the string truncated to the given length.
// If the string is already shorter than the given length, it is returned
// unchanged, along with a true "ok" value.
// This operates on runes, not bytes, so it is safe for multi-byte characters.
func truncatedCopy(s string, maxLen uint) (string, bool) {
	u := []rune(s)
	if uint(len(u)) > maxLen {
		return string(u[:maxLen]), false
	}
	return s, true
}
