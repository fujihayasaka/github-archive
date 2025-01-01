package ctxstash

import (
	"context"
	"errors"
	"testing"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/require"
)

// Define a very simple interface to test with.
type describer interface {
	Describe() string
}

type describable struct {
}

func (d describable) Describe() string {
	return "some description"
}

func TestStash_WithFields(t *testing.T) {
	ctx := context.Background()

	key1 := kvp.String("hello", "world")
	key2 := kvp.String("bonjour", "le monde")

	want1 := []kvp.Field{key1}
	want2 := []kvp.Field{key1, key2}

	ctx1 := WithFields(ctx, key1)
	ctx2 := WithFields(ctx1, key2)

	gotKey1 := From(ctx1).Fields()
	require.Equal(t, want1, gotKey1)
	gotKey2 := From(ctx2).Fields()
	require.Equal(t, want2, gotKey2)
}

func TestStash_WithFields_Duplicates(t *testing.T) {
	ctx := context.Background()

	key1 := kvp.String("hello", "world")
	key2 := kvp.Int("hello", 42)

	want := []kvp.Field{key2}

	ctx = WithFields(ctx, key1)
	ctx = WithFields(ctx, key2)

	got := From(ctx).Fields()
	require.Equal(t, want, got)
}

func TestStash_WithPopulatedFields(t *testing.T) {
	ctx := context.Background()

	var populatedDescriber describer = describable{}
	var nilDescriber describer = nil

	var populatedSlice []int = []int{1, 2, 3}
	var nilSlice []int = nil
	var emptySlice []int = []int{}

	var populatedMap map[string]int = make(map[string]int, 0)
	populatedMap["c"] = 3
	var nilMap map[string]int = nil
	var emptyMap map[string]int = make(map[string]int, 0)

	a := kvp.String("populatedString", "data")
	b := kvp.String("emptyString", "")
	c := kvp.String("anotherPopulatedString", "moredata")
	d := kvp.Err(errors.New("some error"))
	e := kvp.Err(nil) // This won't get pruned.  kvp.Err substitutes "<nil>"
	f := kvp.Any("populatedInterface", populatedDescriber)
	g := kvp.Any("emptyInterface", nilDescriber)

	// When it comes to slices and maps, consider them populated even if they're empty.
	h := kvp.Any("populatedSlice", populatedSlice)
	i := kvp.Any("nilSlice", nilSlice) // This won't get pruned.  When it comes to slice instantiation, nil is effectively shorthand for empty.
	j := kvp.Any("emptySlice", emptySlice)

	k := kvp.Any("populatedMap", populatedMap)
	l := kvp.Any("nilMap", nilMap) // This won't get pruned.  When it comes to map instantiation, nil is effectively shorthand for empty.
	m := kvp.Any("emptyMap", emptyMap)
	ctx = WithPopulatedFields(ctx, a, b, c, d, e, f, g, h, i, j, k, l, m)

	want := []kvp.Field{a, c, d, e, f, h, i, j, k, l, m}
	got := From(ctx).Fields()
	require.Equal(t, want, got)
}

func TestStash_WithPopulatedFields_Empty(t *testing.T) {
	// ensure WithPopulatedFields is effectively a no-op when no fields are supplied.
	ctx := context.Background()
	ctx = WithPopulatedFields(ctx)
	got := From(ctx).Fields()
	require.Empty(t, got)
}

func TestStash_Tags(t *testing.T) {
	ctx := context.Background()

	tag1 := stats.Tags{"hello": "world"}
	tag2 := stats.Tags{"bonjour": "le monde"}

	want1 := tag1
	want2 := tag1.Merge(tag2)

	ctx1 := WithTags(ctx, tag1)
	ctx2 := WithTags(ctx1, tag2)

	gotTags1 := From(ctx1).Tags()
	require.Equal(t, want1, gotTags1)
	gotTags2 := From(ctx2).Tags()
	require.Equal(t, want2, gotTags2)
}

func TestStash_Tags_Duplicate(t *testing.T) {
	ctx := context.Background()

	tag1 := stats.Tags{"hello": "world"}
	tag2 := stats.Tags{"hello": "le monde"}

	want := stats.Tags{"hello": "le monde"}

	ctx = WithTags(ctx, tag1)
	ctx = WithTags(ctx, tag2)

	got := From(ctx).Tags()
	require.Equal(t, want, got)
}
