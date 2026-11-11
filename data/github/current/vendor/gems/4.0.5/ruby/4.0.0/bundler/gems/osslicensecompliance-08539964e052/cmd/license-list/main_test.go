package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBuildLicenseData_ExclusionsAndUnknown(t *testing.T) {
	t.Parallel()

	spdxIDs := []string{"MIT", "GPL-2.0-only", "Apache-2.0"}
	scancode := map[string]licenseMetadata{
		"MIT": {Name: "MIT License", Category: "Permissive", SourceURL: "https://github.com/aboutcode-org/scancode-licensedb/blob/main/docs/mit.json"},
	}
	excluded := map[string]struct{}{
		"GPL-2.0-only": {},
	}

	overrides := map[string]string{}

	got, warnings, err := buildLicenseData(spdxIDs, scancode, excluded, overrides)
	require.NoError(t, err)

	require.Len(t, got, 2)
	assert.Equal(t, licenseMetadata{Name: "MIT License", Category: "Permissive", SourceURL: "https://github.com/aboutcode-org/scancode-licensedb/blob/main/docs/mit.json"}, got["MIT"])
	assert.Equal(t, licenseMetadata{Name: "Apache-2.0", Category: "Unknown"}, got["Apache-2.0"])
	_, hasExcluded := got["GPL-2.0-only"]
	assert.False(t, hasExcluded)

	assert.Len(t, warnings, 2)
	assert.Contains(t, warnings[0], "excluded SPDX license")
	assert.Contains(t, strings.Join(warnings, "\n"), "missing scancode metadata for \"Apache-2.0\"")
}

func TestBuildLicenseData_AppliesSpdxCategoryOverrides(t *testing.T) {
	t.Parallel()

	const licenseNoScancode = "License-No-Scancode-Record"

	spdxIDs := []string{"MIT", licenseNoScancode}
	scancode := map[string]licenseMetadata{
		"MIT": {Name: "MIT License", Category: "Permissive", SourceURL: "https://github.com/aboutcode-org/scancode-licensedb/blob/main/docs/mit.json"},
	}
	excluded := map[string]struct{}{}
	overrides := map[string]string{
		"MIT":             "Copyleft",
		licenseNoScancode: "Permissive",
	}

	got, warnings, err := buildLicenseData(spdxIDs, scancode, excluded, overrides)
	require.NoError(t, err)
	assert.Empty(t, warnings)

	// Override with scancode data: preserves scancode Name and SourceURL
	assert.Equal(t, "Copyleft", got["MIT"].Category)
	assert.Equal(t, "MIT License", got["MIT"].Name)
	assert.Equal(t, "https://github.com/aboutcode-org/scancode-licensedb/blob/main/docs/mit.json", got["MIT"].SourceURL)

	// Override without scancode data: falls back to spdxID as Name, empty SourceURL
	assert.Equal(t, "Permissive", got[licenseNoScancode].Category)
	assert.Equal(t, licenseNoScancode, got[licenseNoScancode].Name)
	assert.Equal(t, "", got[licenseNoScancode].SourceURL)
}

func TestBuildLicenseData_InvalidOverrideCategoryReturnsError(t *testing.T) {
	t.Parallel()

	spdxIDs := []string{"MIT"}
	scancode := map[string]licenseMetadata{
		"MIT": {Name: "MIT License", Category: "Permissive", SourceURL: "https://github.com/aboutcode-org/scancode-licensedb/blob/main/docs/mit.json"},
	}
	excluded := map[string]struct{}{}
	overrides := map[string]string{"MIT": "Not a real category"}

	_, _, err := buildLicenseData(spdxIDs, scancode, excluded, overrides)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "has no description mapping")
}

func TestRenderTypeScript_Deterministic(t *testing.T) {
	t.Parallel()

	input := map[string]licenseMetadata{
		"Apache-2.0": {Name: "Apache License 2.0", Category: "Permissive"},
		"MIT":        {Name: "MIT License", Category: "Permissive"},
		"Zlib":       {Name: "zlib License", Category: "Permissive"},
	}

	out1, err := renderTypeScript(input)
	require.NoError(t, err)

	out2, err := renderTypeScript(input)
	require.NoError(t, err)

	assert.Equal(t, string(out1), string(out2))
	assert.Contains(t, string(out1), "export const categoryDescriptions")
	assert.Contains(t, string(out1), "export const licensesById")
	assert.Contains(t, string(out1), "export function categoryForLicense")
	assert.Contains(t, string(out1), "export function categoriesWithLicenses")
}

func TestScancodeGitHubURL(t *testing.T) {
	t.Parallel()

	assert.Equal(t,
		"https://github.com/aboutcode-org/scancode-licensedb/blob/main/docs/mit.json",
		scancodeGitHubURL("scancode-licensedb-main/docs/mit.json"),
	)
	assert.Equal(t,
		"https://github.com/aboutcode-org/scancode-licensedb/blob/main/docs/mit.json",
		scancodeGitHubURL("scancode-licensedb-v3.0/docs/mit.json"),
	)
	assert.Equal(t,
		"https://github.com/aboutcode-org/scancode-licensedb/blob/main/path.json",
		scancodeGitHubURL("unexpected/path.json"),
	)
	assert.Equal(t, "noprefix.json", scancodeGitHubURL("noprefix.json"))
}

func TestIsScancodeLicenseJSON(t *testing.T) {
	t.Parallel()

	assert.True(t, isScancodeLicenseJSON("scancode-licensedb-main/docs/mit.json"))
	assert.False(t, isScancodeLicenseJSON("scancode-licensedb-main/docs/index.json"))
	assert.False(t, isScancodeLicenseJSON("scancode-licensedb-main/something/mit.json"))
	assert.False(t, isScancodeLicenseJSON("scancode-licensedb-main/docs/mit.yml"))
}

func TestLoadScancodeBySpdx_RejectsOversizedResponse(t *testing.T) {
	t.Parallel()

	const testMaxSize int64 = 1024
	body := make([]byte, testMaxSize+1)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	}))
	defer srv.Close()

	_, err := loadScancodeBySpdx(context.Background(), srv.Client(), srv.URL, testMaxSize)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "exceeds")
}
