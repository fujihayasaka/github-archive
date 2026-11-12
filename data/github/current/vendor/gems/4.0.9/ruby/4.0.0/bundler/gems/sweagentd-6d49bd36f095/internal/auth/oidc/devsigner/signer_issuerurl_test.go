package devsigner

import (
	"fmt"
	"os"
	"testing"
)

func TestIssuerURL_ExplicitOverride(t *testing.T) {
	got := IssuerURL("https://custom-issuer.example.com", "https://api.githubcopilot.com", 2208)
	want := "https://custom-issuer.example.com"
	if got != want {
		t.Errorf("IssuerURL() = %q, want %q", got, want)
	}
}

func TestIssuerURL_ExplicitOverrideTrailingSlash(t *testing.T) {
	got := IssuerURL("https://custom-issuer.example.com/", "", 2208)
	want := "https://custom-issuer.example.com"
	if got != want {
		t.Errorf("IssuerURL() = %q, want %q", got, want)
	}
}

func TestIssuerURL_FromCopilotAPIURL(t *testing.T) {
	t.Setenv("CODESPACE_NAME", "")
	t.Setenv("GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN", "")

	tests := []struct {
		name       string
		copilotAPI string
		want       string
	}{
		{
			name:       "production",
			copilotAPI: "https://api.githubcopilot.com",
			want:       "https://api.githubcopilot.com/agents/swe",
		},
		{
			name:       "proxima",
			copilotAPI: "https://copilot-api.tenant.ghe.com",
			want:       "https://copilot-api.tenant.ghe.com/agents/swe",
		},
		{
			name:       "trailing slash stripped",
			copilotAPI: "https://api.githubcopilot.com/",
			want:       "https://api.githubcopilot.com/agents/swe",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := IssuerURL("", tt.copilotAPI, 2208)
			if got != tt.want {
				t.Errorf("IssuerURL(%q) = %q, want %q", tt.copilotAPI, got, tt.want)
			}
		})
	}
}

func TestIssuerURL_Codespace(t *testing.T) {
	t.Setenv("CODESPACE_NAME", "my-codespace")
	t.Setenv("GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN", "app.github.dev")

	got := IssuerURL("", "", 2208)
	want := "https://my-codespace-2208.app.github.dev"
	if got != want {
		t.Errorf("IssuerURL() = %q, want %q", got, want)
	}
}

func TestIssuerURL_Localhost(t *testing.T) {
	t.Setenv("CODESPACE_NAME", "")
	t.Setenv("GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN", "")

	got := IssuerURL("", "", 2208)
	want := "http://localhost:2208"
	if got != want {
		t.Errorf("IssuerURL() = %q, want %q", got, want)
	}
}

func TestIssuerURL_PartialCodespaceEnv(t *testing.T) {
	t.Setenv("CODESPACE_NAME", "my-codespace")
	os.Unsetenv("GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN") //nolint:tenv // intentionally testing partial env

	got := IssuerURL("", "", 3000)
	want := fmt.Sprintf("http://localhost:%d", 3000)
	if got != want {
		t.Errorf("IssuerURL() = %q, want %q", got, want)
	}
}
