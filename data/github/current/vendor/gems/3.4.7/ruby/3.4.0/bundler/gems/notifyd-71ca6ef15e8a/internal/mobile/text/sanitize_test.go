package text

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestFormatNotificationBody(t *testing.T) {
	r := require.New(t)
	tests := []struct {
		name           string
		input          string
		expectedOutput string
	}{
		{
			name:           "Empty string",
			input:          "",
			expectedOutput: "",
		},
		{
			name:           "Plain text",
			input:          "testing abc",
			expectedOutput: "testing abc",
		},
		{
			name:           "Decodes HTML entities",
			input:          "this &amp; that",
			expectedOutput: "this & that",
		},
		{
			name:           "Strips html tags",
			input:          "<b>bold text</b>",
			expectedOutput: "bold text",
		},
		{
			name:           "Strips markdown string",
			input:          "#### (created by pirateipsum.me)\n Prow scuttle parrel provost Sail ho shrouds spirits **boom** mizzenmast yardarm.",
			expectedOutput: "(created by pirateipsum.me)\n\nProw scuttle parrel provost Sail ho shrouds spirits boom mizzenmast yardarm.",
		},
		{
			name:           "Truncates string",
			input:          "Prow scuttle parrel provost Sail ho shrouds spirits boom mizzenmast yardarm. Pinnace holystone mizzenmast quarter crows nest nipperkin grog yardarm hempen halter furl. Swab barque interloper chantey doubloon starboard grog black jack gangway rutters. Deadlights jack lad schooner scallywag dance the hempen jig carouser broadside cable strike colors. Bring a spring upon her cable grog holystone blow the man down spanker Shiver me timbers to go onto account lookout wherry doubloon chase. Belay yo-ho-ho keelhaul squiffy black spot yardarm spyglass sheet transom heave to.",
			expectedOutput: "Prow scuttle parrel provost Sail ho shrouds spirits boom mizzenmast yardarm. Pinnace holystone mizzenmast quarter crows nest nipperkin grog yardarm hempen halter furl. Swab barque interloper chantey doubloon starboard grog black jack gangway rutters. Deadlights jack lad schooner scallywag dance the hempen jig carouser broadside cable strike colors. Bring a spring upon her cable grog holystone blow the man down spanker Shiver me timbers to go onto account lookout wherry doubloon chase. Belay …",
		},
		{
			name:           "Handles cross-site scripting",
			input:          "<a href=\"javascript:alert('XSS1')\" onmouseover=\"alert('XSS2')\">XSS<a>",
			expectedOutput: "XSS",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			r.Equal(test.expectedOutput, Sanitize(test.input), test.name)
		})
	}
}
