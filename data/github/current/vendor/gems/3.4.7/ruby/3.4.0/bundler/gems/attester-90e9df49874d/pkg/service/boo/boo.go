package boo

import (
	"context"
	"fmt"

	proto "github.com/github/attester/gen/go/attester/v0"
)

// HelloName will echo whatever name it is given in a canned message.
func (boo *Boo) HelloName(_ context.Context, req *proto.HelloNameRequest) (*proto.HelloNameResponse, error) {
	message := fmt.Sprintf("Hello, %v!", req.GetName())
	return &proto.HelloNameResponse{Message: message}, nil
}

// Foo will raise exception.
func (boo *Boo) Error(_ context.Context, _ *proto.HelloNameRequest) (*proto.HelloNameResponse, error) {
	return nil, fmt.Errorf("raised exception")
}
