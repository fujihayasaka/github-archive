package stats

import (
	"net"
	"testing"

	"github.com/stretchr/testify/require"
)

// This package implements a mock statsd server. Its functionality is only meant
// to be used in tests in order to make sure that the `o11y/stats` library is
// properly configured.
//
// It works by spawning an UDP server on 0.0.0.0:7777 and then waiting for a
// message to be sent there.
//
// Once the message arrives it is stored on a buffer that can be read with the
// `recv()` method.
type mockStatsd struct {
	buf  []byte
	conn *net.UDPConn
	msg  chan string
	sent chan bool
}

// start spawns a mockStatsd server and sets it up to wait a message.
func (s *mockStatsd) start() {
	go func() {
		// Wait until a message arrives
		<-s.sent
		n, _, _ := s.conn.ReadFromUDP(s.buf)

		// Pass the received message to the msg channel so that it can be read from
		// outside of the go routine.
		s.msg <- string(s.buf[0:n])
	}()
}

// stop shutsdown the server and closes the connection
func (s *mockStatsd) stop(t *testing.T) {
	r := require.New(t)
	err := s.conn.Close()
	r.NoError(err)
}

// wait uses the given function to send a message to the server and then
// notifies that the message has been sent
func (s *mockStatsd) wait(sendFunc func()) {
	sendFunc()

	s.sent <- true
}

// recv returns the value that has been received as a message on the mock
// server.
//
// It does so by blocking until a message appears on the `msg` channel.
func (s *mockStatsd) recv() string {
	return <-s.msg
}

func newStatsdMock(t *testing.T, addr string) *mockStatsd {
	r := require.New(t)
	udpAddress, err := net.ResolveUDPAddr("udp", addr)
	r.NoError(err)

	conn, err := net.ListenUDP("udp", udpAddress)
	r.NoError(err)

	sent := make(chan bool)
	msg := make(chan string)
	buf := make([]byte, 512)

	return &mockStatsd{
		buf:  buf,
		conn: conn,
		msg:  msg,
		sent: sent,
	}
}
