// Command license-list generates TypeScript license category data for github-ui.
package main

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/github/go-spdx/v2/spdxexp/spdxlicenses"
)

const (
	defaultScancodeZipURL = "https://github.com/aboutcode-org/scancode-licensedb/archive/refs/heads/main.zip"
	defaultTimeout        = 60 * time.Second
	maxZipBytes           = 100 * 1024 * 1024 // 100MB upper bound for the scancode zip download.
	maxZipEntryBytes      = 1 * 1024 * 1024   // 1MB upper bound per zip entry to guard against zip bombs.
	outputFileMode        = 0o644             // World-readable since the generated file is manually copied into other projects.
)

// Keep this hardcoded list explicit and reviewed.
var excludedSpdxIDs = map[string]struct{}{}

// spdxCategoryOverrides allows manually overriding category assignments for specific SPDX IDs.
// Keep this list explicit and reviewed for exceptions where upstream category data is not helpful.
var spdxCategoryOverrides = map[string]string{
	"any-OSI":              "Permissive", // "any-OSI" just means any OSI-approved license, so people could choose a permissive one from that set.
	"any-OSI-perl-modules": "Permissive", // same rationale as "any-OSI"
	"MakeIndex":            "Copyleft",   // Unclear why the category didn't make it across: https://github.com/aboutcode-org/scancode-licensedb/blob/main/docs/makeindex.LICENSE
}

var categoryDescriptions = map[string]string{
	"Commercial":       "High risk",
	"Copyleft":         "High risk",
	"Non-commercial":   "High risk",
	"Copyleft limited": "Requires review",
	"Free restricted":  "Requires review",
	"Proprietary free": "Requires review",
	"Permissive":       "Safe for most",
	"Public domain":    "Safe for most",
	"Source available": "Requires review",
	"Unknown":          "Requires review",
}

type licenseMetadata struct {
	Name      string
	Category  string
	SourceURL string
}

type scancodeLicense struct {
	Name           string `json:"name"`
	Category       string `json:"category"`
	SPDXLicenseKey string `json:"spdx_license_key"`
}

func main() {
	err := run(os.Args[1:], os.Stdout, os.Stderr, &http.Client{Timeout: defaultTimeout})
	if err != nil {
		fmt.Fprintf(os.Stderr, "license-list failed: %v\n", err) //nolint:revive // error path output
		os.Exit(1)
	}
}

func run(args []string, stdout, stderr io.Writer, client *http.Client) error {
	fs := flag.NewFlagSet("license-list", flag.ContinueOnError)
	fs.SetOutput(stderr)

	outPath := fs.String("out", "-", "Output file path, or '-' for stdout")
	scancodeZipURL := fs.String("scancode-zip-url", defaultScancodeZipURL, "URL to scancode-licensedb zip archive")
	err := fs.Parse(args)
	if err != nil {
		return err
	}

	spdxIDs := spdxlicenses.GetLicenses()
	records, err := loadScancodeBySpdx(context.Background(), client, *scancodeZipURL, maxZipBytes)
	if err != nil {
		return fmt.Errorf("load scancode data: %w", err)
	}

	licenses, warnings, err := buildLicenseData(spdxIDs, records, excludedSpdxIDs, spdxCategoryOverrides)
	if err != nil {
		return err
	}

	for _, warning := range warnings {
		_, _ = fmt.Fprintf(stderr, "warning: %s\n", warning) //nolint:revive // warning output
	}

	output, err := renderTypeScript(licenses)
	if err != nil {
		return err
	}

	if *outPath == "-" {
		_, err = stdout.Write(output)
		return err
	}

	err = os.WriteFile(*outPath, output, outputFileMode)
	if err != nil {
		return fmt.Errorf("write output: %w", err)
	}
	return nil
}

func loadScancodeBySpdx(ctx context.Context, client *http.Client, zipURL string, maxZipBytes int64) (map[string]licenseMetadata, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, zipURL, http.NoBody)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("download zip: %w", err)
	}
	defer resp.Body.Close() //nolint:errcheck // best-effort close

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status downloading zip: %s", resp.Status)
	}

	content, err := io.ReadAll(io.LimitReader(resp.Body, maxZipBytes+1))
	if err != nil {
		return nil, fmt.Errorf("read zip response: %w", err)
	}

	if int64(len(content)) > maxZipBytes {
		return nil, fmt.Errorf("zip response exceeds maximum size of %d bytes", maxZipBytes)
	}

	reader, err := zip.NewReader(bytes.NewReader(content), int64(len(content)))
	if err != nil {
		return nil, fmt.Errorf("open zip: %w", err)
	}

	records := make(map[string]licenseMetadata)
	for _, file := range reader.File {
		if !isScancodeLicenseJSON(file.Name) {
			continue
		}

		if file.UncompressedSize64 > maxZipEntryBytes {
			return nil, fmt.Errorf("zip entry %s exceeds maximum uncompressed size (%d bytes)", file.Name, maxZipEntryBytes)
		}

		rc, err := file.Open()
		if err != nil {
			return nil, fmt.Errorf("open zip file %s: %w", file.Name, err)
		}

		var parsed scancodeLicense
		decodeErr := json.NewDecoder(io.LimitReader(rc, maxZipEntryBytes+1)).Decode(&parsed)
		closeErr := rc.Close()
		if decodeErr != nil {
			return nil, fmt.Errorf("decode %s: %w", file.Name, decodeErr)
		}
		if closeErr != nil {
			return nil, fmt.Errorf("close %s: %w", file.Name, closeErr)
		}

		spdxID := strings.TrimSpace(parsed.SPDXLicenseKey)
		if spdxID == "" {
			continue
		}

		if _, exists := records[spdxID]; !exists {
			records[spdxID] = licenseMetadata{
				Name:      strings.TrimSpace(parsed.Name),
				Category:  strings.TrimSpace(parsed.Category),
				SourceURL: scancodeGitHubURL(file.Name),
			}
		}
	}

	if len(records) == 0 {
		return nil, fmt.Errorf("no scancode SPDX records found in zip %q", zipURL)
	}

	return records, nil
}

func scancodeGitHubURL(zipPath string) string {
	_, relativePath, found := strings.Cut(zipPath, "/")
	if !found {
		return zipPath
	}
	return "https://github.com/aboutcode-org/scancode-licensedb/blob/main/" + relativePath
}

func isScancodeLicenseJSON(path string) bool {
	if !strings.HasSuffix(path, ".json") {
		return false
	}
	if strings.HasSuffix(path, "index.json") {
		return false
	}
	// GitHub zip adds a top-level "<repo>-<branch>/" directory.
	// The API JSON files currently live in docs/.
	return strings.Contains(path, "/docs/")
}

func buildLicenseData(
	spdxIDs []string,
	scancodeBySpdx map[string]licenseMetadata,
	excluded map[string]struct{},
	overrides map[string]string,
) (map[string]licenseMetadata, []string, error) {
	output := make(map[string]licenseMetadata, len(spdxIDs))
	warnings := make([]string, 0)

	for _, spdxID := range spdxIDs {
		if _, isExcluded := excluded[spdxID]; isExcluded {
			warnings = append(warnings, fmt.Sprintf("excluded SPDX license %q", spdxID))
			continue
		}

		// overrides work even if the license is missing from scancode
		if override, ok := overrides[spdxID]; ok {
			if _, ok := categoryDescriptions[override]; !ok {
				return nil, nil, fmt.Errorf("override category %q for %s has no description mapping", override, spdxID)
			}
			meta := licenseMetadata{
				Name:     spdxID,
				Category: override,
			}
			if record, found := scancodeBySpdx[spdxID]; found {
				meta.Name = record.Name
				meta.SourceURL = record.SourceURL
			}
			if meta.Name == "" {
				meta.Name = spdxID
			}
			output[spdxID] = meta
			continue
		}

		record, found := scancodeBySpdx[spdxID]
		if !found {
			output[spdxID] = licenseMetadata{
				Name:     spdxID,
				Category: "Unknown",
			}
			warnings = append(warnings, fmt.Sprintf("missing scancode metadata for %q, using Unknown category", spdxID))
			continue
		}

		mappedCategory := mapScancodeCategory(record.Category)

		if _, ok := categoryDescriptions[mappedCategory]; !ok {
			if record.SourceURL != "" {
				return nil, nil, fmt.Errorf("category %q for %s has no description mapping (source: %s)", mappedCategory, spdxID, record.SourceURL)
			}
			return nil, nil, fmt.Errorf("category %q for %s has no description mapping", mappedCategory, spdxID)
		}

		name := record.Name
		if name == "" {
			name = spdxID
		}

		output[spdxID] = licenseMetadata{
			Name:      name,
			Category:  mappedCategory,
			SourceURL: record.SourceURL,
		}
	}

	sort.Strings(warnings)
	return output, warnings, nil
}

func mapScancodeCategory(category string) string {
	switch category {
	case "Source-available":
		return "Source available"
	case "Free Restricted":
		return "Free restricted"
	case "Copyleft Limited":
		return "Copyleft limited"
	case "Public Domain":
		return "Public domain"
	case "Non-Commercial":
		return "Non-commercial"
	case "Proprietary Free":
		return "Proprietary free"
	case "":
		return "Unknown"
	default:
		return category
	}
}

func renderTypeScript(licensesByID map[string]licenseMetadata) ([]byte, error) {
	ids := make([]string, 0, len(licensesByID))
	categorySet := map[string]struct{}{}
	for id, meta := range licensesByID {
		ids = append(ids, id)
		categorySet[meta.Category] = struct{}{}
	}
	sort.Strings(ids)

	categories := make([]string, 0, len(categorySet))
	for category := range categorySet {
		categories = append(categories, category)
	}
	sort.Strings(categories)

	lines := []string{
		"// Code generated by cmd/license-list in osslicensecompliance. DO NOT EDIT.",
		"",
		"export const categoryDescriptions: Record<string, string> = {",
	}
	for _, category := range categories {
		description, ok := categoryDescriptions[category]
		if !ok {
			return nil, fmt.Errorf("missing description for category %q", category)
		}
		lines = append(lines, "  "+singleQuote(category)+": "+singleQuote(description)+",")
	}
	lines = append(lines, "}", "", "export const licensesById: Record<string, {name: string; category: string}> = {")
	for _, id := range ids {
		meta := licensesByID[id]
		lines = append(lines, "  "+singleQuote(id)+": {name: "+singleQuote(meta.Name)+", category: "+singleQuote(meta.Category)+"},")
	}
	lines = append(lines,
		"}",
		"",
		"export function categoryForLicense(spdxId: string): string | undefined {",
		"  return licensesById[spdxId]?.category",
		"}",
		"",
		"export function categoriesWithLicenses(): Array<{",
		"  category: string",
		"  description: string",
		"  licenses: Array<{id: string; name: string}>",
		"}> {",
		"  const grouped: Record<string, Array<{id: string; name: string}>> = {}",
		"  for (const [id, info] of Object.entries(licensesById)) {",
		"    ;(grouped[info.category] ??= []).push({id, name: info.name})",
		"  }",
		"  return Object.keys(grouped)",
		"    .sort((a, z) => a.localeCompare(z))",
		"    .map(category => ({",
		"      category,",
		"      description: categoryDescriptions[category] ?? '',",
		"      licenses: (grouped[category] ?? []).sort((a, z) => a.name.localeCompare(z.name) || a.id.localeCompare(z.id)),",
		"    }))",
		"}",
	)

	return []byte(strings.Join(lines, "\n") + "\n"), nil
}

func singleQuote(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, "'", `\'`)
	return "'" + s + "'"
}
