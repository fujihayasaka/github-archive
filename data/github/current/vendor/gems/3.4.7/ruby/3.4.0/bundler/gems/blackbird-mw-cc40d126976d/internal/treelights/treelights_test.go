package treelights

import (
	"testing"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"

	"github.com/stretchr/testify/require"
)

func TestAddHighlightTokens(t *testing.T) {
	content := AddHighlightTokens(&pb.GitDocumentMatch{ //nolint:exhaustruct
		Content: []byte("line one\nline two\nline three"),
		TermMatches: []*pb.Range{
			// NOTE: this range gets ignored, since it's not part of a snippet
			{Start: 5, End: 8},
			{Start: 14, End: 17},
		},
		ScoringInfo: &pb.ScoringInfo{
			Snippets: []*pb.Snippet{
				{Start: 9, End: 17},
			},
		},
	})

	expected := "line one\nline \u001e\u001ftwo\u001f\u001e\nline three"
	require.Equal(t, expected, string(content))
}

func TestAddHighlightTokensIgnoreOverlapping(t *testing.T) {
	content := AddHighlightTokens(&pb.GitDocumentMatch{ //nolint:exhaustruct
		Content: []byte("line one\nline two\nline three"),
		TermMatches: []*pb.Range{
			{Start: 14, End: 17},
			// Note, this match overlaps, so it gets ignored
			{Start: 15, End: 25},
		},
		ScoringInfo: &pb.ScoringInfo{
			Snippets: []*pb.Snippet{
				{Start: 9, End: 17},
			},
		},
	})

	expected := "line one\nline \u001e\u001ftwo\u001f\u001e\nline three"
	require.Equal(t, expected, string(content))
}

func TestBugFixDisplayWidth80(t *testing.T) {
	content := AddHighlightTokens(&pb.GitDocumentMatch{ //nolint:exhaustruct
		Content: []byte(`<?php

define('SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL', 'sample_service_abcd_fox_event_type_kill');
a b c
`),
		TermMatches: []*pb.Range{
			{Start: 15, End: 54},
			{Start: 58, End: 97},
		},
		ScoringInfo: &pb.ScoringInfo{
			Snippets: []*pb.Snippet{
				{Start: 7, End: 86},
			},
		},
	})

	expected := "<?php\n\ndefine('\u001e\u001fSAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL\u001f\u001e', '\u001e\u001fsample_service_abcd_fox_event_type_kill\u001f\u001e');\na b c\n"
	require.Equal(t, expected, string(content))
}

func TestBugFixDisplayWidth80MoreMatches(t *testing.T) {
	content := AddHighlightTokens(&pb.GitDocumentMatch{ //nolint:exhaustruct
		Content: []byte(`<?php

define('SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL', 'sample_service_abcd_fox_event_type_kill');

sample_service_abcd_fox_event_type_kill

a b c
`),
		TermMatches: []*pb.Range{
			{Start: 15, End: 54},
			{Start: 58, End: 97},
			{Start: 102, End: 141},
		},
		ScoringInfo: &pb.ScoringInfo{
			Snippets: []*pb.Snippet{
				{Start: 7, End: 86},
				{Start: 102, End: 141},
			},
		},
	})

	expected := "<?php\n\ndefine('\u001e\u001fSAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL\u001f\u001e', '\u001e\u001fsample_service_abcd_fox_event_type_kill\u001f\u001e');\n\n\u001e\u001fsample_service_abcd_fox_event_type_kill\u001f\u001e\n\na b c\n"
	require.Equal(t, expected, string(content))
}

func TestBugFixDisplayWidth120(t *testing.T) {
	content := AddHighlightTokens(&pb.GitDocumentMatch{ //nolint:exhaustruct
		Content: []byte(`<?php

define('SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL', 'sample_service_abcd_fox_event_type_kill');
`),
		TermMatches: []*pb.Range{
			{Start: 15, End: 54},
			{Start: 58, End: 97},
		},
		ScoringInfo: &pb.ScoringInfo{
			Snippets: []*pb.Snippet{
				{Start: 0, End: 102},
			},
		},
	})

	expected := "<?php\n\ndefine('\u001e\u001fSAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL\u001f\u001e', '\u001e\u001fsample_service_abcd_fox_event_type_kill\u001f\u001e');\n"
	require.Equal(t, expected, string(content))
}
