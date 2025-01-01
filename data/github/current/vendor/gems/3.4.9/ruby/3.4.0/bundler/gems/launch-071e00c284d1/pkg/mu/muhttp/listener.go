package muhttp

import (
	"net"
)

// NewListener creates a new listener for the address.
func NewListener(address string) (net.Listener, error) {
	return net.Listen("tcp", address)
}
