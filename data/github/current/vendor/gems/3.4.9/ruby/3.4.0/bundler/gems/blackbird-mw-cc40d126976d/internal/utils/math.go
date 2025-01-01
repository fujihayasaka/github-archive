package utils

// Because go doesn't care to provide min max for various type

// Max returns the larger of x or y.
func Max(x, y uint32) uint32 {
	if x < y {
		return y
	}
	return x
}

// Min returns the smaller of x or y.
func Min(x, y uint32) uint32 {
	if x > y {
		return y
	}
	return x
}
