/*
Package errors provides an implementation of Go's error interface that is customized to notifyd
needs.

Most of it is influenced by github.com/pkg/errors and Go's additions to errors on Go 1.13
https://go.dev/blog/go1.13-errors

Specially it relies heavily on errors.Wrap() and errors.As().

errors.As(err error, target interface{}) bool returns true when the given error is the type of the
given target and also assigns the first error on the chain that matches this check to the target.

Example:

	err := somethingThatFails()
	var e *Error
	if errors.As(err, &e) {
		fmt.Printf("it is an *Error %v\n", e)
	}

errors.Wrap(err error, msg string) error wraps the message from the passed error in the given msg.
I.e. if the error message is "oops" and the extra is "boom" the resulting error will be "boom: oops"

Our goals with this package are that all generic error functionality is encapsulated here and that
we avoid needing to import multiple error packages to use them.

The implementation it contains uses the Error struct and it is structured as follows:
  - Uses fmt.Errorf + the %w verb for wrapping
  - Provides a With(opts ...Option) method that can be used to apply different options over a given
    error.
  - New options can be added by just creating new Option functions and modifying Error accordingly.

New Error can be created by using New or Newf as well as wrapping existing errors through Wrap and
Wrapf.

Ideally any error generated outside of notifyd (that is, by Go code that is either not written in
our internal packages or packages that are generated) should be wrapped into an Error and then
applied the necessary options.

Those options are:

- Marking it as retriable if this error would mean that a message has to be retried.

Examples:

	start := time.Now()
	err := CallToFCM()
	if err != nil {
	  return errors.Wrap(err, "calling FCM").With(errors.MarkAsRetriable())
	}

You can find more examples of usage on the tests for this same package.
*/
package errors
