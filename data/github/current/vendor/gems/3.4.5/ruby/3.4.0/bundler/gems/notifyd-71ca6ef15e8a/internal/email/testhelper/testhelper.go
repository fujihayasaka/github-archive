// Package testhelper contains test helpers for the email package.
package testhelper

import (
	"errors"
	"fmt"
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

// Fixture represents a test fixture.
type Fixture struct {
	Dir  string
	Name string
	Ext  string
}

// Dirname returns the fixtures directory name.
func (fx *Fixture) Dirname() string {
	if fx.Dir != "" {
		return fx.Dir
	}

	return "testdata"
}

// Extension returns the fixture extension.
func (fx *Fixture) Extension() string {
	if fx.Ext != "" {
		return fx.Ext
	}

	return ".txt"
}

// Filename returns the fixture filename.
func (fx *Fixture) Filename() string {
	return fmt.Sprintf("%s%s%s%s", fx.Dirname(), string(os.PathSeparator), fx.Name, fx.Extension())
}

/*
IsEqualToFixture checks if come content is equal to the contents of a fixture file.

Example:

	testhelper.IsEqualToFixture(t, &testhelper.Fixture{Name: "email_primer"}, mailBody)

Some tests, especially around Mail body composition, generate a big
blob of text. Fixtures help to move the noise from the test to dedicated files.
Mail bodies in particular use CRLF to indicate new lines, which works better with
files in DOS format.

NOTE: In order for git to respect CRLF chars, these fixture files must be declared in the
.gitattributes file with something like this:

	internal/email/body/testdata/email*.txt text eol=crlf

If you need to modify the fixture file and add new carriage returns it can be done on Vim like
editors by using CTRL-V CTRL-M

Fixture files are by default located in a directory called `testdata/`
at the same level as the running test, with the extension `.txt`.

For example a fixture called `email_primer` will be located by default in:
testdata/email_primer.txt

To define another extension or directory, pass the Dir and Ext fields
to the Fixture struct.

If a fixture doesn't exist, this function will try to create it for the first time,
including the directory. It will use the provided `actual` bytes as the body.
This is helpful if you know the data is correct on a first run, but it's hard to create
the fixture by hand.
*/
func IsEqualToFixture(t *testing.T, fixture *Fixture, actual []byte) {
	t.Helper()
	expected, err := os.ReadFile(fixture.Filename())
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			require.NoError(t, err, "the fixture file couldn't be opened")
		}

		t.Logf(
			"WARNING: The fixture %s doesn't exist, it will be created with the following content:\n%s",
			fixture.Filename(),
			string(actual),
		)

		// Try to create the directory
		if err := os.Mkdir(fixture.Dirname(), 0o777); err != nil && !errors.Is(err, os.ErrExist) { //nolint:gosec // permissions necessary to create via docker
			require.NoError(t, err, "the fixture data dir couldn't be created")
		}

		// Try to write the file
		if err := os.WriteFile(fixture.Filename(), actual, 0o600); err != nil {
			require.NoError(t, err, "the fixture couldn't be created")
		}

		require.Fail(t, "the fixture has been created, rerun the test to use it")
	}

	require.Equal(t, string(expected), string(actual))
}
