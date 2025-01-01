package types

type BeforeAfterSHA struct {
	Before CommitSha
	After  CommitSha
}

func BeforeAfterSHAFromStrings(before string, after string) BeforeAfterSHA {
	return BeforeAfterSHA{CommitSha(before), CommitSha(after)}
}

func (b BeforeAfterSHA) IsZeroValue() bool {
	return b.Before.IsZeroValue() && b.After.IsZeroValue()
}
