package models

import (
	"reflect"
	"testing"
)

func TestSortImageVersionsByVersion(t *testing.T) {
	versions := []*ImageVersion{
		{
			Version: "1.0.0",
		},
		{
			Version: "0.1.0",
		},
		{
			Version: "0.0.1",
		},
	}

	expected := []*ImageVersion{
		{
			Version: "1.0.0",
		},
		{
			Version: "0.1.0",
		},
		{
			Version: "0.0.1",
		},
	}

	SortImageVersionsByVersion(versions)

	if !reflect.DeepEqual(expected, versions) {
		t.Errorf("expected %v but got %v", expected, versions)
	}
}

func TestSortImageVersionsByVersionRandom(t *testing.T) {
	versions := []*ImageVersion{
		{
			Version: "0.1.0",
		},
		{
			Version: "1.0.0",
		},
		{
			Version: "0.0.1",
		},
	}

	expected := []*ImageVersion{
		{
			Version: "1.0.0",
		},
		{
			Version: "0.1.0",
		},
		{
			Version: "0.0.1",
		},
	}

	SortImageVersionsByVersion(versions)

	if !reflect.DeepEqual(expected, versions) {
		t.Errorf("expected %v but got %v", expected, versions)
	}
}

func TestSortImageVersionsByVersionDecsending(t *testing.T) {
	versions := []*ImageVersion{
		{
			Version: "1.0.0",
		},
		{
			Version: "0.1.0",
		},
		{
			Version: "0.0.1",
		},
	}

	expected := []*ImageVersion{
		{
			Version: "1.0.0",
		},
		{
			Version: "0.1.0",
		},
		{
			Version: "0.0.1",
		},
	}

	SortImageVersionsByVersion(versions)

	if !reflect.DeepEqual(expected, versions) {
		t.Errorf("expected %v but got %v", expected, versions)
	}
}

func TestSortImageVersionsByVersionInvalid(t *testing.T) {
	versions := []*ImageVersion{
		{
			Version: "",
		},
		{
			Version: "1.0.0",
		},
		{
			Version: "0.1.0",
		},
		{
			Version: "",
		},
		{
			Version: "0.0.1",
		},
	}

	expected := []*ImageVersion{
		{
			Version: "1.0.0",
		},
		{
			Version: "0.1.0",
		},
		{
			Version: "0.0.1",
		},
		{
			Version: "",
		},
		{
			Version: "",
		},
	}

	SortImageVersionsByVersion(versions)

	if !reflect.DeepEqual(expected, versions) {
		t.Errorf("expected %v but got %v", expected, versions)
	}
}

func TestSortImageVersionsByMacOSFormat(t *testing.T) {
	versions := []*ImageVersion{
		{
			Version: "2025.1102.1",
		},
		{
			Version: "2024.0102.1",
		},
		{
			Version: "2024.0101.1",
		},
		{
			Version: "2024.0102.2",
		},
	}

	expected := []*ImageVersion{
		{
			Version: "2025.1102.1",
		},
		{
			Version: "2024.0102.2",
		},
		{
			Version: "2024.0102.1",
		},
		{
			Version: "2024.0101.1",
		},
	}

	SortImageVersionsByVersion(versions)

	if !reflect.DeepEqual(expected, versions) {
		t.Errorf("expected %v but got %v", expected, versions)
	}
}
