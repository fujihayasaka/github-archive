package codediff

// NeedlemanWunsch returns the edit distance between two tokenizers.
// for instance
// |       |   | G | C | A | T | G | C | A |
// |-------|---|---|---|---|---|---|---|---|
// |       | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
// | **G** | 1 | 0 | 1 | 1 | 1 | 0 | 1 | 1 |
// | **A** | 2 | 1 | 1 | 1 | 2 | 1 | 1 | 1 |
// | **T** | 3 | 2 | 2 | 2 | 1 | 2 | 2 | 2 |
// | **T** | 4 | 3 | 3 | 3 | 2 | 2 | 3 | 3 |
// | **A** | 5 | 4 | 4 | 3 | 3 | 3 | 3 | 3 |
// | **C** | 6 | 5 | 4 | 4 | 4 | 4 | 3 | 4 |
// | **A** | 7 | 6 | 5 | 4 | 5 | 5 | 4 | 3 |
//
// will return 3. as the best matching requires 3 operations.
func NeedlemanWunsch(needle, haystack Tokenizer) int {
	haystackT := haystack.Tokens()
	needleT := needle.Tokens()

	// when haystack is empty, we need to insert all of needle
	if len(haystackT) == 0 {
		return len(needleT)
	}

	dp := make([][]int, len(needleT)+1)
	for i := range dp {
		dp[i] = make([]int, len(haystackT)+1)
	}

	for i := 0; i <= len(needleT); i++ {
		for j := 0; j <= len(haystackT); j++ {
			switch {
			case i == 0:
				dp[i][j] = 0
			case j == 0:
				dp[i][j] = i
			default:
				match := 1
				if needleT[i-1] == haystackT[j-1] {
					match = 0
				}
				dp[i][j] = min(dp[i-1][j-1]+match, // substitution
					min(dp[i-1][j]+1, // deletion
						dp[i][j-1]+1)) // insertion
			}
		}
	}

	// Find the best matching end-offset
	best := 0
	for i := 1; i <= len(haystackT); i++ {
		if dp[len(needleT)][i] < dp[len(needleT)][best] {
			best = i
		}
	}

	return dp[len(needleT)][best]
}
