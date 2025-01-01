package alerts

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

var classifyTests = []struct {
	in  string
	out ts.FileClassification
}{
	{"/this/is/doc/file.c", ts.FileClassification{"documentation"}},
	{"/this/is/docs/file.c", ts.FileClassification{"documentation"}},
	{"docs/file.c", ts.FileClassification{"documentation"}},
	{"/this/is/documentation/file.c", ts.FileClassification{"documentation"}},
	{"/this/is/documentations/file.c", ts.FileClassification{"documentation"}},
	{"/this/is/not_documentations/file.c", ts.FileClassification{}},

	{"/this/is/a.min.js", ts.FileClassification{"generated"}},
	{"/this/is/a-min.js", ts.FileClassification{"generated"}},
	{"/this/is/discord.min.release.js", ts.FileClassification{"generated"}},
	{"/this/is/discord.min.3.3.1.js", ts.FileClassification{"generated"}},
	{"discord.min.3.3.1.js", ts.FileClassification{"generated"}},
	{"/this/is/discord.min..js", ts.FileClassification{"generated"}},

	{"/this/is/notmin.js", ts.FileClassification{}},
	{"/this/is/not/min.js", ts.FileClassification{}},
	{"/this/is/not/a.min.c", ts.FileClassification{}},
	{"/this/is/not/discord.minjs", ts.FileClassification{}},
	{"/this/is/not/discord.min-js", ts.FileClassification{}},
	{"/this/is/not/spec.ts", ts.FileClassification{}},
	{"/this/is/not/filespec.ts", ts.FileClassification{}},

	{"/this/is/test/file.c", ts.FileClassification{"test"}},
	{"/this/is/tests/file.c", ts.FileClassification{"test"}},
	{"/this/is/test_cases/file.py", ts.FileClassification{"test"}},
	{"/this/is/file.spec.ts", ts.FileClassification{"test"}},
	{"/this/is/spec.spec.ts", ts.FileClassification{"test"}},

	{"/this/is/third-party/file.c", ts.FileClassification{"library"}},
	{"/this/is/thirdparty/file.c", ts.FileClassification{"library"}},
	{"/this/is/third_party/file.c", ts.FileClassification{"library"}},
	{"/this/is/external/file.c", ts.FileClassification{"library"}},
	{"/this/is/vendor/file.c", ts.FileClassification{"library"}},
	{"vendor/gopkg.in/yaml.v2/apic.go", ts.FileClassification{"library"}},
	{"/this/is/3rdparty/file.c", ts.FileClassification{"library"}},
	{"/this/is/a-1.0.1/library", ts.FileClassification{"library"}},
	{"/this/is/not-a10/library", ts.FileClassification{}},
	{"/this/is/node_modules/file.js", ts.FileClassification{"library"}},
	{"node_modules/file.js", ts.FileClassification{"library"}},
	{"/this/is/bower_components/file.js", ts.FileClassification{"library"}},
	{"lodash-3.4.1/library.js", ts.FileClassification{"library"}},

	{"/src/benchmark/a.js", ts.FileClassification{"test"}},
	{"/src/benchmarks/b.js", ts.FileClassification{"test"}},
	{"benchmarks/first/bench.js", ts.FileClassification{"test"}},
	{"/src/benchmark.js", ts.FileClassification{}},
	{"/src/bench/a.js", ts.FileClassification{}},

	{"spec/file.rb", ts.FileClassification{"test"}},
	{"/src/spec/helpers/file.rb", ts.FileClassification{"test"}},

	{"/this/is/test/discord.min.3.3.1.js", ts.FileClassification{"generated", "test"}},
	{"/this/is/test/discord-3.3.1/discord.min.3.3.1.js", ts.FileClassification{"generated", "test", "library"}},

	{"/src/ProjectA.Tests/ProjectA.Tests.cs", ts.FileClassification{"test"}},
	{"/src/ProjectA.Test/ProjectA.cs", ts.FileClassification{"test"}},

	{"/src/beetle_test.go", ts.FileClassification{"test"}},
}

func TestDocClassification(t *testing.T) {
	for _, p := range classifyTests {
		require.Equal(t, p.out, classifyFileByPath(p.in), p)
	}
}
