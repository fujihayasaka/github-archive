package firewall

import (
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/stretchr/testify/require"
)

func TestFirewallComment(t *testing.T) {
	t.Run("has domains and first 3 commands which triggered", func(t *testing.T) {
		blockedRequests := []BlockedRequest{
			{
				Domains:   "example.com",
				Cmd:       "curl example.com",
				BlockedAt: "dns",
			},
			{
				Domains:   "example.com",
				Cmd:       "wget example.com",
				BlockedAt: "dns",
			},
			{
				Domains:   "example.com",
				Cmd:       "zget example.com",
				BlockedAt: "dns",
			},
			{
				Domains:   "example.com",
				Cmd:       "qget example.com",
				BlockedAt: "dns",
			},
			{
				Domains:   "github.com",
				URL:       "https://github.com/bob",
				Cmd:       "curl https://github.com/bob",
				BlockedAt: "http",
			},
			{
				Domains: "github.com,bing.com",
			},
			{
				Domains: "example.com",
			},
			{
				Domains: "None",
			},
			{
				Domains: "peanut.info,butter.info,jelly.info.",
			},
		}
		job := &jobs.Job{OwnerID: 1, RepoID: 2}
		comment, err := GenerateFirewallComment(blockedRequests, job, "golly", "gosh")
		require.NoError(t, err)
		require.NotEmpty(t, comment)
		require.Contains(t, comment, "<summary>Firewall rules")
		require.Contains(t, comment, "[Copilot coding agent settings](https://github.com/golly/gosh/settings/copilot/coding_agent)")
		require.Equal(t, 1, strings.Count(comment, "`example.com`"), "The top level domain should appear once")
		require.Equal(t, 1, strings.Count(comment, "`github.com`"))
		require.Equal(t, 1, strings.Count(comment, "bing.com"))
		require.Equal(t, 1, strings.Count(comment, "peanut.info"))
		require.Equal(t, 1, strings.Count(comment, "butter.info"))
		require.Equal(t, 1, strings.Count(comment, "jelly.info"))
		require.NotEqual(t, 1, strings.Count(comment, "jelly.info."))
		require.NotContains(t, comment, "None")
		// Validate triggering command added
		exampleOutputWithTriggeringCmd := "> - `example.com`" +
			"\n>   - Triggering command: `curl example.com` (dns block)" +
			"\n>   - Triggering command: `wget example.com` (dns block)" +
			"\n>   - Triggering command: `zget example.com` (dns block)"
		require.Contains(t, comment, exampleOutputWithTriggeringCmd)
		require.NotContains(t, comment, "qget example.com", "This is the fourth command which invokes example.com, we should only include first 3")
		require.Contains(t, comment, "> - `https://github.com/bob`\n>", "Skip Triggering command output when cmd not is present")
	})

	t.Run("has IPs", func(t *testing.T) {
		blockedRequests := []BlockedRequest{
			{
				IP: "127.0.0.1",
			},
			{
				IP: "192.168.1.1",
			},
			{
				IP: "192.168.1.1",
			},
			{
				IP: "192.168.1.1",
			},
			{
				IP: "192.168.1.1",
			},
			{
				IP: "127.0.0.1",
			},
		}
		comment, err := GenerateFirewallComment(blockedRequests, &jobs.Job{OwnerID: 1, RepoID: 2}, "golly", "gosh")
		require.NoError(t, err)
		require.NotEmpty(t, comment)
		require.Contains(t, comment, "<summary>Firewall rules")
		require.Equal(t, 1, strings.Count(comment, "127.0.0.1"))
		require.Equal(t, 1, strings.Count(comment, "192.168.1.1"))
	})

	t.Run("has URLs", func(t *testing.T) {
		blockedRequests := []BlockedRequest{
			{
				URL: "https://127.0.0.1",
			},
			{
				URL: "https://127.0.0.1",
			},
			{
				URL: "https://192.168.1.1",
			},
			{
				URL: "https://192.168.1.1",
			},
		}
		comment, err := GenerateFirewallComment(blockedRequests, &jobs.Job{OwnerID: 1, RepoID: 2}, "golly", "gosh")
		require.NoError(t, err)
		require.NotEmpty(t, comment)
		require.Contains(t, comment, "<summary>Firewall rules")
		require.Equal(t, 1, strings.Count(comment, "https://127.0.0.1"))
		require.Equal(t, 1, strings.Count(comment, "https://192.168.1.1"))
	})

	t.Run("trims space from command", func(t *testing.T) {
		blockedRequests := []BlockedRequest{
			{
				Cmd:     "   curl example.com  ",
				Domains: "this.localhost",
			},
		}
		comment, err := GenerateFirewallComment(blockedRequests, &jobs.Job{OwnerID: 1, RepoID: 2}, "golly", "gosh")
		require.NoError(t, err)
		require.Contains(t, comment, ">   - Triggering command: `curl example.com`")
	})

	t.Run("has correct precedence", func(t *testing.T) {
		blockedRequests := []BlockedRequest{
			{
				URL:     "https://this.localhost",
				IP:      "127.0.0.1",
				Domains: "this.localhost",
			},
			{
				IP:      "127.0.0.1",
				Domains: "that.localhost",
			},
		}
		comment, err := GenerateFirewallComment(blockedRequests, &jobs.Job{OwnerID: 1, RepoID: 2}, "golly", "gosh")
		require.NoError(t, err)
		require.NotEmpty(t, comment)
		require.Contains(t, comment, "<summary>Firewall rules")
		require.Equal(t, 1, strings.Count(comment, "https://this.localhost"))
		require.Equal(t, 1, strings.Count(comment, "that.localhost"))
	})

	t.Run("parses correctly", func(t *testing.T) {
		blockedRequests := []BlockedRequest{
			{
				URL:     "https://this.localhost",
				IP:      "127.0.0.1",
				Domains: "this.localhost",
			},
			{
				URL:     "https://this.website",
				IP:      "93.0.100.1",
				Domains: "this.website",
			},
		}
		l := ParseLocations(blockedRequests)
		require.Equal(t, 2, len(l))
	})

	t.Run("ignores domains", func(t *testing.T) {
		blockedRequests := []BlockedRequest{
			{
				URL: "https://fwupd.org",
			},
			{
				Domains: "fwupd.org",
			},
			{
				URL: "_https._tcp.apt.releases.hashicorp.com",
			},
			{
				Domains: "_https._tcp.apt.releases.hashicorp.com",
			},
			{
				URL: "https://ishouldbeincluded.com",
			},
			{
				Domains: "ishouldbeincluded.com",
			},
			{
				IP: "127.0.0.1",
			},
		}
		l := ParseLocations(blockedRequests)
		require.Equal(t, 3, len(l))
	})
}
