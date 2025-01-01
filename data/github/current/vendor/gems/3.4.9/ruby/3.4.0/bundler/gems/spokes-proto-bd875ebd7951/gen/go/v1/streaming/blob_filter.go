package streaming

type BlobFilterOpt func(*BlobFilter)

func WithPlainTextOnly() BlobFilterOpt {
	return func(f *BlobFilter) {
		f.PlainTextOnly = true
	}
}

func WithUTF8Only() BlobFilterOpt {
	return func(f *BlobFilter) {
		f.Utf8Only = true
	}
}

func WithMaxLineLength(l int64) BlobFilterOpt {
	return func(f *BlobFilter) {
		f.MaxLineLength = l
	}
}

func WithMaxSize(s int64) BlobFilterOpt {
	return func(f *BlobFilter) {
		f.MaxSize = s
	}
}

func WithMinSize(s int64) BlobFilterOpt {
	return func(f *BlobFilter) {
		f.MinSize = s
	}
}

func WithTruncation(s uint32) BlobFilterOpt {
	return func(f *BlobFilter) {
		f.TruncateAt = s
	}
}
