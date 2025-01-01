package crpc

import (
	"context"
	"fmt"
)

// CommandFunc describes a chatops command implementation
type CommandFunc func(context.Context, *CommandRequest) (*CommandResponse, error)

// ListMethod describes how to call a Chatops RPC method in a Namespace.
type ListMethod struct {
	Name   string   `json:"-"`
	Regex  string   `json:"regex"`
	Params []string `json:"params"`
	Path   string   `json:"path,omitempty"`
	Help   string   `json:"help,omitempty"`
	do     CommandFunc
}

// Do performs the chatops command and returns the response
func (m *ListMethod) Do(ctx context.Context, req *CommandRequest) (*CommandResponse, error) {
	if m.do == nil {
		return &CommandResponse{
			Result: fmt.Sprintf("Method %s received: %+v", m.Name, req),
		}, nil
	}

	return m.do(ctx, req)
}

// On seds the CommandFunc for the method
func (m *ListMethod) On(fn CommandFunc) {
	m.do = fn
}

// ListResponse describes the methods that a Chatops RPC server supports.
type ListResponse struct {
	Version       int                    `json:"version"`
	Namespace     string                 `json:"namespace"`
	Methods       map[string]*ListMethod `json:"methods"`
	ErrorResponse string                 `json:"error_response,omitempty"`
	Help          string                 `json:"help,omitempty"`
}
