package manifests

const (
	// this is a sentinel value for Git object IDs that represents
	// an initial push to a ref, or a deleted ref, in PostReceive
	// (beforeOID, afterOID) ranges
	ZeroOID = "0000000000000000000000000000000000000000"

	// this is the "empty Git tree" OID, another sentinel value. Example:
	// echo $(git hash-object -t tree --stdin </dev/null)
	EmptyTreeOID = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
)
