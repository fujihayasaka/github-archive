package stats

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewClient(t *testing.T) {
	r := require.New(t)

	t.Run("builds a stats.Client", func(t *testing.T) {
		client, err := NewClient("0.0.0.0:7777", "notifyd", "test")
		r.NoError(err)
		server := newStatsdMock(t, "0.0.0.0:7777")

		// Run the mock server and start the client process
		server.start()
		client.Run()
		defer server.stop(t)
		defer client.Stop()

		// Send the message
		server.wait(func() { client.Counter("msg", nil, 1) })

		// Read the stored message from the server
		received := server.recv()

		r.Contains(received, "notifyd.msg")
		r.Contains(received, "deploy_env:test")
	})

	t.Run("returns an error with empty address", func(t *testing.T) {
		client, err := NewClient("", "notifyd", "test")
		r.Nil(client)
		r.Error(err)
	})
}
