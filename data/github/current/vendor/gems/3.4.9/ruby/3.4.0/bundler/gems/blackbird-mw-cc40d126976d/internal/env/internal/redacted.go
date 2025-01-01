package internal

// redacted is a struct that implements envconfig's Decoder interface but
// outputs <REDACTED> when logging. Use it for credentials and secrets that
// shouldn't be output in the logs.
type redacted struct {
	value string
}

func (r *redacted) Decode(value string) error {
	*r = redacted{value: value}
	return nil
}

func (r redacted) String() string {
	return "<REDACTED>"
}

// redactedBytes is a struct that implements envconfig's Decoder interface but
// outputs <REDACTED> when logging. Use it for credentials and secrets that
// shouldn't be output in the logs.
type redactedBytes struct {
	value []byte
}

func (r *redactedBytes) Decode(value string) error {
	*r = redactedBytes{value: []byte(value)}
	return nil
}

func (r redactedBytes) String() string {
	return "<REDACTED>"
}
