package hydro

import (
	"context"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-stats"
)

type consumerGroupHandler struct {
	mux      sync.RWMutex
	done     <-chan struct{}
	cancel   func()
	running  bool
	stopped  bool
	session  sarama.ConsumerGroupSession
	messages chan *sarama.ConsumerMessage
	stats    stats.Client
}

func newConsumerGroupHandler(statsClient stats.Client) *consumerGroupHandler {
	return &consumerGroupHandler{
		stats: statsClient,
	}
}

func (c *consumerGroupHandler) Setup(session sarama.ConsumerGroupSession) error {
	c.mux.Lock()
	defer c.mux.Unlock()
	var ctx context.Context
	ctx, c.cancel = context.WithCancel(session.Context())
	c.done = ctx.Done()
	c.session = session
	c.running = true
	if c.messages == nil {
		c.messages = make(chan *sarama.ConsumerMessage)
	}
	return nil
}

func (c *consumerGroupHandler) Cleanup(_ sarama.ConsumerGroupSession) error {
	c.mux.Lock()
	defer c.mux.Unlock()
	c.session = nil
	c.running = false
	return nil
}

func (c *consumerGroupHandler) ConsumeClaim(_ sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	var outChan chan<- *sarama.ConsumerMessage = c.messages
	for {
		select {
		case <-c.done:
			return nil
		case message, ok := <-claim.Messages():
			if !ok {
				return nil
			}
			select {
			case <-c.done:
				return nil
			case outChan <- message:
			}
		}
	}
}

func (c *consumerGroupHandler) waitForRunning(ctx context.Context) error {
	var err error
	for {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		c.mux.RLock()
		if c.running {
			break
		}
		if c.stopped {
			err = fmt.Errorf("consumer is stopped")
			break
		}
		c.mux.RUnlock()
		time.Sleep(time.Microsecond)
	}
	c.mux.RUnlock()
	return err
}

func (c *consumerGroupHandler) ReadMessage(ctx context.Context) (Message, error) {
	err := c.waitForRunning(ctx)
	if err != nil {
		return Message{}, err
	}
	select {
	case <-ctx.Done():
		return Message{}, ctx.Err()
	case cm, ok := <-c.messages:
		if !ok {
			return Message{}, io.EOF
		}
		return ConsumerMessageToMessage(cm, c.stats), nil
	}
}

var errSessionNotStarted = errors.New("session has not yet started")

func (c *consumerGroupHandler) MarkMessage(msg Message) error {
	c.mux.RLock()
	defer c.mux.RUnlock()
	if c.session == nil {
		return errSessionNotStarted
	}
	c.session.MarkOffset(msg.Topic, msg.Partition, msg.Offset+1, "")
	return nil
}

func (c *consumerGroupHandler) CommitOffsets() error {
	c.mux.RLock()
	defer c.mux.RUnlock()
	if c.session == nil {
		return errSessionNotStarted
	}
	c.session.Commit()
	return nil
}

func (c *consumerGroupHandler) Close() error {
	c.mux.Lock()
	defer c.mux.Unlock()
	if c.stopped {
		return fmt.Errorf("already closed")
	}
	if c.cancel == nil {
		return nil
	}
	close(c.messages)
	c.cancel()
	c.stopped = true
	return nil
}
