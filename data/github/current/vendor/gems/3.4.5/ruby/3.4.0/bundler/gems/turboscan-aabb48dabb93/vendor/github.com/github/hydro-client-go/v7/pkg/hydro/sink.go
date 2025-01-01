package hydro

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
)

var errClosedSink = errors.New("closed sink")

// Sink is the interface for writing Messages.
type Sink interface {
	Write(Message) error
	WriteBatch([]Message) error
	Flush() error
	Close() error
}

// MemorySink implements the Sink interface for writing Messages to a channel.
type MemorySink struct {
	ch chan<- Message

	once sync.Once
	done chan struct{}
}

// NewMemorySink returns a sink backed by the channel. If the channel is nil it
// will return an error. The caller is responsible for the lifecycle of the
// channel. If the channel is not drained it may result in a deadlock.
func NewMemorySink(ch chan<- Message) (*MemorySink, error) {
	if ch == nil {
		return nil, errors.New("channel must not be nil")
	}

	return &MemorySink{
		ch:   ch,
		done: make(chan struct{}),
	}, nil
}

// Write attempts to send the message on the MemorySink's channel. When the
// MemorySink is closed calls to Write will return an error. If the channel
// send panics it will be recovered and returned as an error.
func (ms *MemorySink) Write(msg Message) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = errClosedSink
		}
	}()

	// ensure not closed before attempting write
	select {
	case <-ms.done:
		return errClosedSink
	default:
	}

	select {
	case <-ms.done:
		return errClosedSink
	case ms.ch <- msg:
		return nil
	}
}

// WriteBatch attempts to send messages on the MemorySink's channel. When the
// MemorySink is closed calls to WriteBatch will return an error. If the channel
// send panics it will be recovered and returned as an error.
func (ms *MemorySink) WriteBatch(msgs []Message) (err error) {
	for _, msg := range msgs {
		if err := ms.Write(msg); err != nil {
			return err
		}
	}

	return nil
}

// Flush has no effect.
func (ms *MemorySink) Flush() error {
	return nil
}

// Close closes the MemorySink for writing. The caller is responsible for
// closing and draining the channel. Close can safely be called multiple times.
func (ms *MemorySink) Close() error {
	ms.once.Do(func() {
		close(ms.done)
	})
	return nil
}

// LogSink implements the Sink interface for writing Messages using a Logger.
type LogSink struct {
	logger Logger
	once   sync.Once
	closed bool
}

// NewLogSink returns a LogSink backed by a Logger.
func NewLogSink(l Logger) *LogSink {
	return &LogSink{logger: l}
}

// Write writes the Message in a custom log format using the Logger's Println
// method. Calls to write when closed will return an error.
func (ls *LogSink) Write(msg Message) error {
	if ls.closed {
		return errClosedSink
	}
	ls.logger.Println(formatLogMessage(msg))
	return nil
}

// WriteBatch writes messages in a custom log format using the Logger's Println
// method. Calls to WriteBatch when closed will return an error.
func (ls *LogSink) WriteBatch(msgs []Message) error {
	for _, msg := range msgs {
		if err := ls.Write(msg); err != nil {
			return err
		}
	}
	return nil
}

// Flush has no effect on a LogSink.
func (ls *LogSink) Flush() error {
	return nil
}

func formatLogMessage(m Message) string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("topic=%q", m.Topic))

	if len(m.Key) > 0 {
		sb.WriteString(fmt.Sprintf(" key=%q", m.Key))
	}

	if m.Metadata != nil {
		if m.Metadata.Partition != nil {
			sb.WriteString(fmt.Sprintf(" partition=%d", *m.Metadata.Partition))
		} else if len(m.Metadata.PartitionKey) > 0 {
			sb.WriteString(fmt.Sprintf(" partitionKey=%q", m.Metadata.PartitionKey))
		}
	}

	if len(m.Headers) > 0 {
		sb.WriteString(fmt.Sprintf(" headers=%v", m.Headers))
	}

	sb.WriteString(fmt.Sprintf(" value=%s", m.Value))
	return sb.String()
}

// Close closes the LogSink causing subsequent calls to Write to return an
// error. It is safe to call Close multiple times.
func (ls *LogSink) Close() error {
	ls.once.Do(func() {
		ls.closed = true
	})
	return nil
}

// FileSink implements the Sink interface for writing Messages encoded as a
// JSON stream to a file.
type FileSink struct {
	file    *os.File
	encoder *json.Encoder
}

// NewFileSink opens the named file for appending. If the file doesn't exist it
// will be created with mode 0644. The caller is responsible for calling Close
// when done writing.
func NewFileSink(filename string) (*FileSink, error) {
	f, err := os.OpenFile(filename, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil, err
	}

	return &FileSink{
		file:    f,
		encoder: json.NewEncoder(f),
	}, nil
}

// Write appends each Message as a JSON stream to the file. If an encode or
// write operation fails there's no guarantee over which messages were
// successfully been written.
func (fs *FileSink) Write(msg Message) error {
	return fs.encoder.Encode(msg)
}

// WriteBatch appends messages as a JSON stream to the file. If an encode or
// write operation fails there's no guarantee over which messages were
// successfully been written.
func (fs *FileSink) WriteBatch(msgs []Message) error {
	for _, msg := range msgs {
		if err := fs.Write(msg); err != nil {
			return err
		}
	}
	return nil
}

// Flush flushes any pending writes in the OS to disk.
func (fs *FileSink) Flush() error {
	return fs.file.Sync()
}

// Close closes the file. Subsequent calls to Close returns os.ErrClosed.
func (fs *FileSink) Close() error {
	return fs.file.Close()
}
