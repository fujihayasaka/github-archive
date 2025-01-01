// These are tests that primarily cover JSON serialization and deserialization
// of the core snapshot types.
package interfaces

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// test that a DependencyNode with no metadata can be serialized and deserialized
func TestDependencyNodeMarshalWithDefaults(t *testing.T) {
	ex := DependencyNode{
		PackageURL: "pkg://example/node@1.1.1",
		// Not specified: Metadata, Relationship, Scope, Dependencies
	}
	j, err := ex.MarshalJSON()
	if err != nil {
		t.Errorf("error marshaling DependencyNode: %v", err)
	}

	var fromJSON map[string]string
	err = json.Unmarshal(j, &fromJSON)
	if err != nil {
		t.Errorf("error unmarshaling DependencyNode: %v", err)
	}

	expectedMap := map[string]string{
		"package_url": ex.PackageURL,
		// Missing: metadata, relationship, scope, dependencies
	}

	assert.Equal(t, expectedMap, fromJSON)
}

func TestDependencyNodePackageName(t *testing.T) {
	examples := []struct {
		desc     string
		purl     string
		expected string
	}{
		{"non-namespaced node package", "pkg:npm/node@1.1.1", "node"},
		{"namespaced node package", "pkg:npm/%40actions/hello@1.1.1", "@actions/hello"},
		{"non-namespaced maven package", "pkg:maven/hello@1.1.1", "hello"},
		{"namespaced maven package", "pkg:maven/com.example/hello@1.1.1", "com.example:hello"},
	}
	for _, example := range examples {
		t.Run(example.purl, func(t *testing.T) {
			node := DependencyNode{
				PackageURL: example.purl,
			}
			assert.Equal(t, example.expected, node.PackageName(), "Failure in "+example.desc)
		})
	}
}

// JSON-deserialized objects are going to be a common theme here,
// so we'll make them a little easier to read.
type object = map[string]interface{}

func TestDependencyNodeMarshalComplete(t *testing.T) {
	ex := DependencyNode{
		PackageURL: "pkg://example/thing@2.2.2",
		Metadata: object{
			"source": "made it up",
		},
		Relationship: Direct,
		Scope:        Development,
		Dependencies: []string{"nokogiri"},
	}
	j, err := ex.MarshalJSON()
	if err != nil {
		t.Errorf("error marshaling DependencyNode: %v", err)
	}

	var fromJSON object
	err = json.Unmarshal(j, &fromJSON)
	if err != nil {
		t.Errorf("error unmarshaling DependencyNode: %v", err)
	}

	expectedMap := object{
		"package_url":  ex.PackageURL,
		"metadata":     object{"source": "made it up"},
		"relationship": "direct",
		"scope":        "development",
		"dependencies": []interface{}{"nokogiri"},
	}

	assert.Equal(t, expectedMap, fromJSON)
}

func TestDependencyNodePurlMarshaling(t *testing.T) {
	badPurl := "pkg:hex/plug_crypto@~> 1.1.1 or ~> 1.2"
	goodPurl := "pkg:hex/plug_crypto@~%3E%201.1.1%20or%20~%3E%201.2"

	badNode := DependencyNode{
		PackageURL: badPurl,
	}

	goodNode := DependencyNode{
		PackageURL: goodPurl,
	}

	badJSON, err := badNode.MarshalJSON()
	require.NoError(t, err)

	goodJSON, err := goodNode.MarshalJSON()
	require.NoError(t, err)

	// The bad PURL should be escaped in the resulting JSON
	assert.Contains(t, string(badJSON), goodPurl)

	// at this point there should be no difference in the resulting JSON
	assert.Equal(t, goodJSON, badJSON)
}

func TestSnapshotMarshalWithDefaults(t *testing.T) {
	ex := Snapshot{
		Version: 0,
		Job: Job{
			Correlator: "job_correlator",
			ID:         "job_id",
			// No HTML URL
		},
		SHA:     "abcd1234",
		Ref:     "refs/heads/main",
		Scanned: time.Now().Round(time.Second),
		// No Detector, Metadata, Manifests
		// ID, RepositoryID and CreatedAt should never appear in JSON
		ID:           1,
		RepositoryID: 2,
		CreatedAt:    time.Time{},
	}

	j, err := ex.MarshalJSON()
	if err != nil {
		t.Errorf("error marshaling Snapshot: %v", err)
	}

	var fromJSON object
	err = json.Unmarshal(j, &fromJSON)
	if err != nil {
		t.Errorf("error unmarshaling Snapshot: %v", err)
	}

	expectedMap := object{
		"version": float64(0),
		"job": object{
			"correlator": "job_correlator",
			"id":         "job_id",
		},
		"sha":     "abcd1234",
		"ref":     "refs/heads/main",
		"scanned": ex.Scanned.Format(time.RFC3339),
	}

	assert.Equal(t, expectedMap, fromJSON)
}

func TestSnapshotMarshalComplete(t *testing.T) {
	ex := Snapshot{
		Version: 0,
		Job: Job{
			Correlator: "job_correlator",
			ID:         "job_id",
			HTMLUrl:    "https://example.com/job_name",
		},
		SHA: "abcd1234",
		Ref: "refs/heads/main",
		Detector: &DetectorMetadata{
			Name:    "detector_name",
			URL:     "https://example.com/detector_name",
			Version: "1.0.0",
		},
		Internal: true,
		Metadata: Metadata{
			"source": "made it up",
		},
		Manifests: Manifests{
			"oid1": &Manifest{
				Name:     "Path1",
				File:     FileInfo{SourceLocation: "Path1"},
				Metadata: Metadata{"oid": "oid1"},
				Resolved: DependencyGraph{
					"somepack1": &DependencyNode{
						PackageURL:   "pkg:example/somepack1@version1",
						Relationship: Direct,
						Scope:        Runtime,
						Metadata:     Metadata{},
						Dependencies: []string{"transitiveDep"},
					},
					"transitiveDep": &DependencyNode{
						PackageURL:   "pkg:example/transitiveDep@1.2.3",
						Relationship: Indirect,
						Scope:        Runtime,
						Metadata:     Metadata{},
						Dependencies: []string{},
					},
				},
			},
		},
		Scanned: time.Now().Round(time.Second),
		// ID, RepositoryID and CreatedAt should never appear in JSON
		ID:           1,
		RepositoryID: 2,
		CreatedAt:    time.Time{},
	}

	j, err := ex.MarshalJSON()
	if err != nil {
		t.Errorf("error marshaling Snapshot: %v", err)
	}

	var fromJSON object
	err = json.Unmarshal(j, &fromJSON)
	if err != nil {
		t.Errorf("error unmarshaling Snapshot: %v", err)
	}

	expectedMap := object{
		"version": float64(0),
		"job": object{
			"correlator": "job_correlator",
			"id":         "job_id",
			"html_url":   "https://example.com/job_name",
		},
		"sha":      "abcd1234",
		"internal": true,
		"ref":      "refs/heads/main",
		"detector": object{
			"name":    "detector_name",
			"url":     "https://example.com/detector_name",
			"version": "1.0.0",
		},
		"metadata": object{
			"source": "made it up",
		},
		"manifests": object{
			"oid1": object{
				"name": "Path1",
				"file": object{
					"source_location": "Path1",
				},
				"metadata": object{
					"oid": "oid1",
				},
				"resolved": object{
					"somepack1": object{
						"package_url":  "pkg:example/somepack1@version1",
						"relationship": "direct",
						"scope":        "runtime",
						"dependencies": []interface{}{"transitiveDep"},
					},
					"transitiveDep": object{
						"package_url":  "pkg:example/transitiveDep@1.2.3",
						"relationship": "indirect",
						"scope":        "runtime",
					},
				},
			},
		},
		"scanned": ex.Scanned.Format(time.RFC3339),
	}

	assert.Equal(t, expectedMap, fromJSON)
}

func TestCanonicalizeForHash(t *testing.T) {
	scannedAt := time.Now().Round(time.Second)
	ex := Snapshot{
		Version: 0,
		Job: Job{
			Correlator: "job_correlator",
			ID:         "job_id",
			HTMLUrl:    "https://example.com/job_name",
		},
		SHA: "abcd1234",
		Ref: "refs/heads/main",
		Detector: &DetectorMetadata{
			Name:    "detector_name",
			URL:     "https://example.com/detector_name",
			Version: "1.0.0",
		},
		Internal: false,
		Metadata: Metadata{
			"source": "made it up",
		},
		Manifests: Manifests{
			"oid1": &Manifest{
				Name:     "Path1",
				File:     FileInfo{SourceLocation: "Path1"},
				Metadata: Metadata{"oid": "oid1"},
				Resolved: DependencyGraph{
					"somepack1": &DependencyNode{
						PackageURL:   "pkg:example/somepack1@version1",
						Relationship: Direct,
						Scope:        Runtime,
						Dependencies: []string{"transitiveDep"},
					},
				},
			},
		},
		Scanned: scannedAt,
		// ID, RepositoryID and CreatedAt should never appear in JSON
		ID:           1,
		RepositoryID: 2,
		CreatedAt:    time.Time{},
	}

	canonicalized1, err := ex.CanonicalizeForHash()
	require.NoError(t, err, "error canonicalizing Snapshot for hash")
	require.NotEmpty(t, canonicalized1, "canonicalized Snapshot should not be empty")

	// verify that the canonicalized bytes are real json and contain the dependencies
	var canonicalizedSnapshot Snapshot
	err = json.Unmarshal(canonicalized1, &canonicalizedSnapshot)
	require.NoError(t, err, "error unmarshaling canonicalized Snapshot")
	assert.Equal(t, ex.Manifests, canonicalizedSnapshot.Manifests, "Manifests should match after canonicalization")

	// verify that CanonicalizeForHash does not modify the original Snapshot
	assert.Equal(t, ex.Job.ID, "job_id", "Job ID should not be modified")
	assert.Equal(t, ex.SHA, "abcd1234", "SHA should not be modified")
	assert.Equal(t, ex.Scanned, scannedAt, "Scanned time should not be modified")

	// verify that we can modify the original Snapshot and still get the same canonicalized bytes
	ex.Job.ID = "new_job_id"
	ex.SHA = "new_sha"
	ex.Scanned = time.Now().Round(time.Second)

	canonicalized2, err := ex.CanonicalizeForHash()
	require.NoError(t, err, "error canonicalizing modified Snapshot for hash")
	assert.Equal(t, canonicalized1, canonicalized2, "canonicalized bytes should be the same after modifying original Snapshot")
}

func TestSnapshotMarshalSkipInternalFalse(t *testing.T) {
	ex := Snapshot{
		Version: 0,
		Job: Job{
			Correlator: "job_correlator",
			ID:         "job_id",
			HTMLUrl:    "https://example.com/job_name",
		},
		SHA: "abcd1234",
		Ref: "refs/heads/main",
		Detector: &DetectorMetadata{
			Name:    "detector_name",
			URL:     "https://example.com/detector_name",
			Version: "1.0.0",
		},
		Internal: false,
		Metadata: Metadata{
			"source": "made it up",
		},
		Manifests: Manifests{
			"oid1": &Manifest{
				Name:     "Path1",
				File:     FileInfo{SourceLocation: "Path1"},
				Metadata: Metadata{"oid": "oid1"},
				Resolved: DependencyGraph{
					"somepack1": &DependencyNode{
						PackageURL:   "pkg:example/somepack1@version1",
						Relationship: Direct,
						Scope:        Runtime,
						Metadata:     Metadata{},
						Dependencies: []string{"transitiveDep"},
					},
				},
			},
		},
		Scanned: time.Now().Round(time.Second),
		// ID, RepositoryID and CreatedAt should never appear in JSON
		ID:           1,
		RepositoryID: 2,
		CreatedAt:    time.Time{},
	}

	j, err := ex.MarshalJSON()
	if err != nil {
		t.Errorf("error marshaling Snapshot: %v", err)
	}

	var fromJSON object
	err = json.Unmarshal(j, &fromJSON)
	if err != nil {
		t.Errorf("error unmarshaling Snapshot: %v", err)
	}

	expectedMap := object{
		"version": float64(0),
		"job": object{
			"correlator": "job_correlator",
			"id":         "job_id",
			"html_url":   "https://example.com/job_name",
		},
		"sha": "abcd1234",
		"ref": "refs/heads/main",
		"detector": object{
			"name":    "detector_name",
			"url":     "https://example.com/detector_name",
			"version": "1.0.0",
		},
		"metadata": object{
			"source": "made it up",
		},
		"manifests": object{
			"oid1": object{
				"name": "Path1",
				"file": object{
					"source_location": "Path1",
				},
				"metadata": object{
					"oid": "oid1",
				},
				"resolved": object{
					"somepack1": object{
						"package_url":  "pkg:example/somepack1@version1",
						"relationship": "direct",
						"scope":        "runtime",
						"dependencies": []interface{}{"transitiveDep"},
					},
				},
			},
		},
		"scanned": ex.Scanned.Format(time.RFC3339),
	}

	assert.Equal(t, expectedMap, fromJSON)
	assert.NotContains(t, fromJSON, "internal")
}
