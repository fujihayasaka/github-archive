package panicmultierrgroup

import (
	"fmt"

	multierror "github.com/hashicorp/go-multierror"
)

// errFromPanic returns the typed error if the recovered panic is an error, otherwise formats as error.
func errFromPanic(p any) error {
	if err, ok := p.(error); ok {
		return err
	}
	return fmt.Errorf("panic: %v", p)
}

// Group wraps the hashicorp/go-multierror group to recover panics and return them as errors
type Group struct {
	multierror.Group
}

// Go calls the given function in a new goroutine.
//
// If the function returns an error it is added to the group multierror which
// is returned by Wait. Any panic is recovered and returned as an error
func (g *Group) Go(f func() error) {
	g.Group.Go(func() (err error) {
		defer func() {
			if p := recover(); p != nil {
				err = errFromPanic(p)
			}
		}()

		return f()
	})
}

// Wait blocks until all function calls from the Go method have returned, then
// returns the multierror.
func (g *Group) Wait() *multierror.Error {
	return g.Group.Wait()
}
