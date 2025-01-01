package reqmeta_test

import (
	"testing"

	gokvp "github.com/github/go-kvp"

	kvp "github.com/github/launch/pkg/mu/reqmeta"
)

func TestTagMerge(t *testing.T) {
	t1 := kvp.Tags{"foo": "bar", "bar": "nope"}
	t2 := kvp.Tags{"bar": "quux"}

	t3 := t1.Merge(t2)

	if len(t1) != 2 {
		t.Error("expected to have 2 tags")
	}

	if len(t2) != 1 {
		t.Error("expected to have 1 tag")
	}

	if len(t3) != 2 {
		t.Error("expected to have 2 tags")
	}

	if t1["bar"] != "nope" {
		t.Error("expected t1 to not be modified")
	}

	if t3["bar"] != "quux" {
		t.Error("expected merged has to have override")
	}
}

func TestCopy(t *testing.T) {
	rmd := kvp.NewRequestMetadata()
	rmd.LogWith(gokvp.String("foo", "bar"))

	rmd2 := rmd.Copy()
	if len(rmd2.LogFields()) != 1 {
		t.Error("expected fields to be retained")
	}
}

func TestLogWith(t *testing.T) {
	rmd := kvp.NewRequestMetadata()

	rmd.LogWith(gokvp.String("foo", "bar"))
	f := rmd.LogFields()

	if len(f) != 1 {
		t.Error("expected a log field")
	}

	if f[0].String() != "bar" {
		t.Error("expected value")
	}
}

func TestTagStatsWith(t *testing.T) {
	rmd := kvp.NewRequestMetadata()

	rmd.TagStatsWith(kvp.Tags{"foo": "bar"})

	s := rmd.StatTags()

	if s["foo"] != "bar" {
		t.Error("expected stat tags to be added")
	}
}
