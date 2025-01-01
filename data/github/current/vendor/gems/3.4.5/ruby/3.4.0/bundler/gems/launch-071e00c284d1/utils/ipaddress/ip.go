package ipaddress

import (
	"encoding/binary"
	"net"

	"github.com/golang/protobuf/ptypes/wrappers"
)

// Prefer BigEndian order, so addresses in the same subnet can be queried with an integer range
// e.g. 10.1.1.0/24 -> [10.1.1.0,10.1.1.255] -> [167837952,167838207]
var byteOrder = binary.BigEndian

// IPV4ToInt converts IPV4 address to an int
func IPV4ToInt(str string) uint32 {
	parsed := net.ParseIP(str)
	if len(parsed) == 0 {
		return 0
	}
	return byteOrder.Uint32(parsed[12:16])
}

// IPV4ToInt converts IPV4 address to a nullable int for protobuf
func IPV4ToIntWrapped(str string) *wrappers.UInt32Value {
	parsed := net.ParseIP(str)
	if len(parsed) == 0 {
		return nil
	}
	return &wrappers.UInt32Value{Value: byteOrder.Uint32(parsed[12:16])}
}

// IntToIPV4 converts an encoded IPV4 address back to usable form
func IntToIPV4(i uint32) net.IP {
	ip := make(net.IP, 4)
	byteOrder.PutUint32(ip, i)
	return ip
}
