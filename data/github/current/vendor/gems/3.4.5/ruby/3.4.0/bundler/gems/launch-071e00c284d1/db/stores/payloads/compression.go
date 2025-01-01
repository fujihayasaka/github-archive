package payloads

type CompressionType int

const (
	// None is the default, uncompressed type.
	CompressionTypeNone CompressionType = iota

	// Snappy refers to the Snappy compression algorithm
	CompressionTypeSnappy
)

// MaxMediumBlobSize is the maximum size in bytes for a MEDIUMBLOB column.
// Taken from: https://dev.mysql.com/doc/refman/5.7/en/storage-requirements.html#data-types-storage-reqs-strings
const MaxMediumBlobSizeBytes = 16777215
