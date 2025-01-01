package kafka

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/proto"
)

// FileConsumer implements the Consumer interface for local testing.
// It uses a local file as the source of messages. Each message is a line in the file.
type FileConsumer struct {
	fp string
}

// NewFileConsumer creates a new FileConsumer.
func NewFileConsumer(fp string) *FileConsumer {
	return &FileConsumer{fp: fp}
}

// Consume reads messages from the file and calls the provided function for each message.
func (c *FileConsumer) Consume(ctx context.Context, fn func(context.Context, []byte) error) error {
	f, err := os.Open(c.fp)
	if err != nil {
		return fmt.Errorf("error opening file: %w", err)
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		payload := scanner.Bytes()

		var e v1.Event
		if err := json.Unmarshal(payload, &e); err != nil {
			return fmt.Errorf("error unmarshaling event: %w", err)
		}

		bytes, err := proto.Marshal(&e)
		if err != nil {
			return fmt.Errorf("error marshaling event: %w", err)
		}

		if err := fn(ctx, bytes); err != nil {
			return err
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("error reading from file: %w", err)
	}

	return nil
}
