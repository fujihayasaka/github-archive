package suggested_fixes

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func TestSerializeSuggestedFix(t *testing.T) {
	sf := &ts.SuggestedFix{
		ID:          ts.SuggestedFixID(1),
		Description: "test desciption",
		Files: []*ts.SuggestedFixFile{
			{
				DiffContent: []byte("--- index.js\n+++ index.js\n@@ -0,0 +1 @@\n+const escape = require('escape-html');\n@@ -4 +5 @@\n-app.get('/', (req, res) => res.send(`Hello, ${req.query.name}!`));\n\\ No newline at end of file\n+app.get('/', (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n\\ No newline at end of file\n"),
				FilePath:    "index.js",
			},
		},
	}

	serialized := serializeSuggestedFix(sf)
	require.Equal(t, sf.Description, serialized.Description)
	expectedDiff := []byte("diff --git a/index.js b/index.js\n--- index.js\n+++ index.js\n@@ -0,0 +1 @@\n+const escape = require('escape-html');\n@@ -4 +5 @@\n-app.get('/', (req, res) => res.send(`Hello, ${req.query.name}!`));\n\\ No newline at end of file\n+app.get('/', (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n\\ No newline at end of file\n")
	require.Equal(t, expectedDiff, serialized.Files[0].DiffContent)
}
