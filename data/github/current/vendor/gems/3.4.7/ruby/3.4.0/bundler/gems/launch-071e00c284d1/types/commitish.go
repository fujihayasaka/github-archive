package types

// Commitish is a ref or a sha.
type Commitish interface {
	isCommitish() // nolint
	String() string
}
