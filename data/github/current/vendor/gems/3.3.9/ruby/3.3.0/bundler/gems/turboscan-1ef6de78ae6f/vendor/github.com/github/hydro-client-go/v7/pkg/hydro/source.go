package hydro

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	pkgerrors "github.com/pkg/errors"
)

var ErrSourceClosed = errors.New("source is closed")

// MessageHandler is a function that allows a user to supply the logic for
// handling a Message.
//
// The value returned by a handler controls stream advancing and message retry
// behavior. When a nil error is returned the stream will advance. When a
// non-nil error is returned the message will be retried.
//
// A context is provided to a handler to signal cancellation. Slower handlers
// should check for cancellation and abandon their message when possible. When
// abandoning a message due to cancellation the context's error must be
// returned.
//
// A handler may be called from a concurrent context. This requires any
// state access or modifications to be protected.
//
// If a handler panics it will be recovered and treated as if the handler
// returned an error.
type MessageHandler func(context.Context, Message) error

// Source is the interface for consuming a Message stream.
type Source interface {
	// Consume starts a long running consumer loop to process a Message stream
	// using a MessageHandler. It returns with no error when it reaches the end
	// of a stream. It returns with an error when the context is canceled or it
	// encounters an unrecoverable error.
	Consume(context.Context, MessageHandler) error
	Close() error
}

type Consumer interface {
	// ReadMessage reads a Message from a stream. It blocks until a Message is
	// read or the context is canceled. If the end of a stream is encountered
	// it returns an io.EOF error.
	ReadMessage(context.Context) (Message, error)

	// MarkMessage marks the Message as being successfully processed. This
	// enables the Message's offset to be committed by implementations that
	// support offset semantics.
	//
	// It returns an error if the Message fails to be marked. This can occur in
	// implementations backed by a Kafka consumer group when trying to commit
	// the offset for topic/partition that is not currently owned by a consumer
	// group session.
	MarkMessage(Message) error
}

func consumeWithHandler(ctx context.Context, logPrintLn func(...interface{}), reporter ErrorReporter, consumer Consumer, fn MessageHandler) error {
	for {
		msg, err := consumer.ReadMessage(ctx)
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}

		for {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			err := recoverAndLogPanic(ctx, func() error {
				return fn(ctx, msg)
			}, logPrintLn, reporter)

			if err == nil {
				markErr := consumer.MarkMessage(msg)
				if markErr != nil {
					logPrintLn(fmt.Sprintf("error marking message: %v", markErr))
				}
				break
			}
		}
	}
}

// MemorySource is the Source implementation that consumes Messages from a
// channel.
type MemorySource struct {
	ch <-chan Message
}

// NewMemorySource returns a MemorySource backed by a directed Message channel.
func NewMemorySource(ch <-chan Message) (*MemorySource, error) {
	if ch == nil {
		return nil, errors.New("channel must not be nil")
	}

	return &MemorySource{ch}, nil
}

// Consume starts a long running consumer loop that receives Messages from its
// channel and processes them using the MessageHandler. It returns with no
// error when the channel is closed and all messages have been handled
// successfully. It may return early with a context error if the context is
// canceled.
//
// To ensure a timely shutdown the caller should check the context for
// cancellation in their MessageHandler implementation.
//
// It processes a single message at a time by applying the MessageHandler. It
// will retry the message until the MessageHandler returns a nil error. If a
// panic occurs in the MessageHandler it will be recovered, logged, and
// retried.
//
// If in-order processing is required Consume must not be called concurrently.
func (ms *MemorySource) Consume(ctx context.Context, fn MessageHandler) error {
	return consumeWithHandler(ctx, log.Println, nilErrorReporter, ms, fn)
}

// ReadMessage reads one message from the source. If ctx is canceled or the source is closed it will
// return an empty message and io.EOF or a context error.
func (ms *MemorySource) ReadMessage(ctx context.Context) (Message, error) {
	select {
	case <-ctx.Done():
		return Message{}, ctx.Err()
	case msg, ok := <-ms.ch:
		if !ok {
			return Message{}, io.EOF
		}
		return msg, nil
	}
}

// MarkMessage does nothing
func (ms *MemorySource) MarkMessage(Message) error {
	return nil
}

// Close has no effect.
func (ms *MemorySource) Close() error {
	return nil
}

// FileSource is the Source implementation that consumes Messages from a file
// encoded as a JSON stream.
type FileSource struct {
	file *os.File
	r    *bufio.Reader
	// TODO: add option to begin reading at an offset
}

// NewFileSource returns a new FileSource that opens the named file for
// reading. The caller is responsible for calling Close.
func NewFileSource(filename string) (*FileSource, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}

	source := &FileSource{
		file: f,
		r:    bufio.NewReader(f),
	}

	return source, nil
}

// Consume starts a long running consumer loop that reads Messages encoded as a
// JSON stream line-by-line and processes them using the MessageHandler. It
// returns with no error when the context has been canceled. It returns an
// error if it encounters an error reading or decoding.
//
// The consumer loop processes a single message at a time. When the
// MessageHandler returns a non-nil error the Message will be retried until it
// returns nil. Panics in the MessageHandler are recovered, logged, and handled
// as an error.
//
// If in-order processing is required Consume must not be called concurrently.
func (fs *FileSource) Consume(ctx context.Context, fn MessageHandler) error {
	return consumeWithHandler(ctx, log.Println, nilErrorReporter, fs, fn)
}

// Close closes the file. Subsequent calls to Close returns os.ErrClosed.
func (fs *FileSource) Close() error {
	return fs.file.Close()
}

// MarkMessage does nothing
func (fs *FileSource) MarkMessage(Message) error {
	return nil
}

// readMessage reads a line from the file into a local buffer. If a read
// encounters an io.EOF, it will sleep and then resume polling for input. Any
// other read error encountered will be returned.
//
// If the context is canceled while polling it will return the context's error.
//
// When a complete line has been read into the local buffer it will be
// unmarshalled as JSON returning the Message or error.
//
// To support reading from a file as an unbounded JSON stream this was
// implemented using a bufio.Reader with manual line reading and unmarshalling.
// This was required since a json.Decoder will not read new data once its
// reader encounters an io.EOF.
func (fs *FileSource) ReadMessage(ctx context.Context) (Message, error) {
	var buf []byte
	for {
		select {
		case <-ctx.Done():
			return Message{}, ctx.Err()
		default:
		}

		line, isPrefix, err := fs.r.ReadLine()
		if err == io.EOF {
			time.Sleep(250 * time.Millisecond)
			continue // continue polling for full line
		} else if err != nil {
			return Message{}, err
		}

		buf = append(buf, line...)
		if !isPrefix && err == nil {
			break // full line has been read
		}
	}

	var m Message
	if err := json.Unmarshal(buf, &m); err != nil {
		return Message{}, fmt.Errorf("unmarshalling JSON: %w", err)
	}
	return m, nil
}

// recoverAndLogPanic runs fn() and returns its error message. If fn() returns
// an error or panics, it will be logged and passed to the given errReporter.
func recoverAndLogPanic(ctx context.Context, fn func() error, logPrintLn func(...interface{}), errReporter ErrorReporter) error {
	err := runWithRecover(fn)
	if err != nil {
		if logPrintLn != nil {
			logPrintLn(err)
		}
		reportErr := errReporter.Report(ctx, err, nil)
		if reportErr != nil && logPrintLn != nil {
			logPrintLn(err)
		}
	}
	return err
}

// runWithRecover runs fn() and returns any error. Panics are recovered and used
// to wrap ErrorPanic so that they can be distinguished if desired.
func runWithRecover(fn func() error) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = pkgerrors.WithStack(fmt.Errorf("%w: %v", ErrorPanic, r))
		}
	}()
	return fn()
}
