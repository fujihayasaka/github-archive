package ts

// Truncate returns a truncated version of the input string.
// This counts the number of runes, rather then the number of bytes,
// and it is equivalent to the following:
//
//	  u := []rune(s)
//		 if uint(len(u)) > size {
//		   return string(u[:size])
//		 }
//		 return s
//
// but works locally on the input slice
func Truncate(s string, size uint) string {
	count := uint(0)
	for idx := range s {
		if count == size {
			return s[:idx]
		}
		count++
	}
	return s
}
