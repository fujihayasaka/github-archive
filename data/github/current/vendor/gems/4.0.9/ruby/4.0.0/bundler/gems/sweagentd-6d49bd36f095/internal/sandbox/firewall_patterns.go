package sandbox

import (
	"embed"
	"net/url"
	"path"
	"strings"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"gopkg.in/yaml.v3"
)

// defaultRuleHostPatterns is the "recommended allowlist" — host patterns
// derived from the YAML rule files embedded under config.DefaultNetworkRules.
// It is loaded once at package init: the source files ship with the binary
// and are validated by tests, so a parse failure here is a build-time
// invariant and is surfaced via panic rather than per-call errors.
var defaultRuleHostPatterns = mustLoadDefaultRuleHostPatterns()

func mustLoadDefaultRuleHostPatterns() []string {
	patterns, err := loadDefaultRuleHostPatterns(config.DefaultNetworkRules, config.DefaultNetworkRulesFolder)
	if err != nil {
		panic(goerrors.Errorf("sandbox: failed to load embedded default network rules: %w", err))
	}
	return patterns
}

// networkRuleSet mirrors the on-disk YAML structure of the default network
// rule files. Only the fields needed to derive host patterns are decoded —
// the Launch sandbox EgressPolicy.HostRule format only matches on host, so
// scheme/path qualifiers from the original schema are intentionally ignored.
type networkRuleSet struct {
	Rules []networkRule `yaml:"rules"`
}

type networkRule struct {
	Kind string          `yaml:"kind"`
	IP   string          `yaml:"ip,omitempty"`
	URL  *networkRuleURL `yaml:"url,omitempty"`
}

type networkRuleURL struct {
	Domain            string `yaml:"domain"`
	AllowAnySubdomain bool   `yaml:"allow-any-subdomain,omitempty"`
}

// loadDefaultRuleHostPatterns parses every YAML file under folder in fs and
// returns a deduped slice of host patterns and IPs. Each http-rule contributes
// its domain (plus "*.domain" when allow-any-subdomain is set). Each ip-rule
// contributes its raw IP. This is the host-only equivalent of the gzipped
// ruleset shipped to the Actions firewall binary via
// config.GenerateEncodedDefaultRulesSetEnv.
func loadDefaultRuleHostPatterns(fs embed.FS, folder string) ([]string, error) {
	files, err := fs.ReadDir(folder)
	if err != nil {
		return nil, goerrors.Errorf("failed to read default network rules directory: %w", err)
	}

	patterns := make([]string, 0)
	for _, file := range files {
		contents, err := fs.ReadFile(path.Join(folder, file.Name()))
		if err != nil {
			return nil, goerrors.Errorf("failed to read default network rules file %s: %w", file.Name(), err)
		}

		var rs networkRuleSet
		err = yaml.Unmarshal(contents, &rs)
		if err != nil {
			return nil, goerrors.Errorf("failed to parse default network rules file %s: %w", file.Name(), err)
		}

		for _, r := range rs.Rules {
			switch r.Kind {
			case "ip-rule":
				if ip := strings.TrimSpace(r.IP); ip != "" {
					patterns = append(patterns, ip)
				}
			case "http-rule":
				if r.URL == nil {
					continue
				}
				domain := strings.TrimSpace(r.URL.Domain)
				if domain == "" {
					continue
				}
				patterns = append(patterns, domain)
				if r.URL.AllowAnySubdomain {
					patterns = append(patterns, "*."+domain)
				}
			default:
				// Unknown rule kinds are ignored; the firewall backend
				// schema is intentionally extensible.
			}
		}
	}

	return dedupePatterns(patterns), nil
}

// extractHostPatterns parses a comma-separated mix of URLs and bare host
// patterns and returns just the host components. Wildcard entries like
// "*.example.com" are preserved as-is. Malformed URLs are silently
// dropped — the same CSV is already validated by upstream config code.
func extractHostPatterns(csv string) []string {
	out := make([]string, 0)
	for raw := range strings.SplitSeq(csv, ",") {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			continue
		}
		// Bare hostnames / IPs (no scheme) — keep as-is.
		if !strings.Contains(entry, "://") {
			out = append(out, entry)
			continue
		}
		u, err := url.Parse(entry)
		if err != nil {
			continue
		}
		if host := u.Hostname(); host != "" {
			out = append(out, host)
		}
	}
	return out
}

// dedupePatterns trims whitespace, removes empty entries, and de-duplicates
// patterns while preserving first-seen order.
func dedupePatterns(in []string) []string {
	seen := make(map[string]struct{}, len(in))
	out := make([]string, 0, len(in))
	for _, p := range in {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		if _, ok := seen[p]; ok {
			continue
		}
		seen[p] = struct{}{}
		out = append(out, p)
	}
	return out
}
