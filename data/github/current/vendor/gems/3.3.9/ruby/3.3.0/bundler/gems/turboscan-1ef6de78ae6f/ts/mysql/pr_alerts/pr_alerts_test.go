package pr_alerts

import (
	"testing"

	"github.com/github/turboscan/ts/proto"
	"github.com/stretchr/testify/require"
)

func TestFileChangesToMaps(t *testing.T) {
	fileChanges := []*proto.FileChange{
		{
			FilePath: "F1",
			Changes:  []*proto.Change{{Added: false, StartLine: 1, EndLine: 1}},
		},
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}

	addedMap, removedMap := fileChangesToMaps(fileChanges)
	require.Equal(t, map[string][]*proto.Change{"F2": fileChanges[1].Changes}, addedMap)
	require.Equal(t, map[string][]*proto.Change{"F1": fileChanges[0].Changes}, removedMap)

	fileChanges = []*proto.FileChange{
		{
			FilePath: "F1",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}

	addedMap, removedMap = fileChangesToMaps(fileChanges)
	require.Equal(t, map[string][]*proto.Change{"F1": fileChanges[0].Changes, "F2": fileChanges[1].Changes}, addedMap)
	require.Len(t, removedMap, 0)
}
