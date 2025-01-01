package crpc

import (
	"errors"
)

var (
	errMethodExists   = errors.New("method exists")
	errMethodNotFound = errors.New("method not found")
)

// Namespace holds a set of ListMethods under Name.
type Namespace struct {
	Name    string
	Help    string
	methods map[string]*ListMethod
}

// NewNamespace creates a new Namespace.
func NewNamespace(n string) *Namespace {
	return &Namespace{
		Name:    n,
		methods: make(map[string]*ListMethod),
	}
}

func (n *Namespace) Register(chatop Chatop) (*ListMethod, error) {
	method, err := n.Add(chatop.Name())
	if err != nil {
		return nil, err
	}
	method.Help = chatop.Help()
	method.Regex = chatop.Regexp()
	method.On(chatop.Handle)

	return method, nil
}

// Add adds a method, name, to the namespace. If a method already exists for
// that name, an error is returneed.
func (n *Namespace) Add(name string) (*ListMethod, error) {
	if _, ok := n.methods[name]; ok {
		return nil, errMethodExists
	}

	m := &ListMethod{Name: name}
	n.methods[name] = m
	return m, nil
}

// Method looks up a method in the namespace. If the method is not found, an
// error is returned.
func (n *Namespace) Method(name string) (*ListMethod, error) {
	if m, ok := n.methods[name]; ok {
		return m, nil
	}
	return nil, errMethodNotFound
}

// Methods returns the underlying map of methods. This should not be modified
// by the caller.
func (n *Namespace) Methods() map[string]*ListMethod {
	return n.methods
}
