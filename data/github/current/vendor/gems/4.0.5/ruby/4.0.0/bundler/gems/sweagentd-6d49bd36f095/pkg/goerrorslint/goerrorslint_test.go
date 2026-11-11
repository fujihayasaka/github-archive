package goerrorslint

import (
	"testing"

	"github.com/stretchr/testify/require"
	"golang.org/x/tools/go/analysis/analysistest"
)

func TestAll(t *testing.T) {
	dir, cleanup, err := analysistest.WriteFiles(map[string]string{
		"test/normal.go": `package test
		import (
			"errors"
			"fmt"
		)

		func foo1() {
			err := errors.New("some error") // want "` + newFound + `"

			_ = fmt.Errorf("some wrap: %w", err) // want "` + errorfFound + `"
		}`,

		"test/alias.go": `package test
		import (
			thiserrors "errors"
			thisfmt "fmt"
		)

		func foo2() {
			err := thiserrors.New("some error") // want "` + newFound + `"

			_ = thisfmt.Errorf("some wrap: %w", err) // want "` + errorfFound + `"
		}`,

		"test/noerrors.go": `package test
		import (
			"fmt"
		)

		func foo3() {
			fmt.Println("Hello world")
		}`,

		"test/noimports.go": `package test
		func foo4() int {
			return 1 + 1
		}`,

		"test/norelevantimports.go": `package test

		import "os"

		func foo5() string {
			wd, _ := os.Getwd()
			return wd
		}`,
	})
	defer cleanup()
	require.NoError(t, err)

	analyzers, err := (&Plugin{}).BuildAnalyzers()
	require.NoError(t, err)

	analysistest.Run(t, dir, analyzers[0], "test")
}
