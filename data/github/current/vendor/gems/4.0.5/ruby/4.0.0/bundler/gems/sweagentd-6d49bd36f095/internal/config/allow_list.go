package config

import (
	"bytes"
	"compress/gzip"
	"embed"
	"encoding/base64"
	"fmt"
	"net/url"
	"path"
	"strings"

	"github.com/github/sweagentd/internal/goerrors"
)

// DefaultNetworkRules holds the recommended (default) firewall network rule
// YAML files embedded at build time. The Actions/Docker launchers ship the
// raw YAML to the firewall binary; the sandbox EgressPolicy builder parses
// it to flat host patterns. See DefaultNetworkRulesFolder for the subdir.
//
//go:embed default_network_rules
var DefaultNetworkRules embed.FS

// DefaultNetworkRulesFolder is the embed.FS subdirectory containing the
// recommended (default) firewall network rule YAML files. Consumers like
// the sandbox EgressPolicy builder iterate these files to derive their
// own backend-specific allowlist representation.
const DefaultNetworkRulesFolder = "default_network_rules"

// DomainIgnoreList contains domains that we do not want to allow by default, but should not show up in the firewall alert.
// This should mainly be things that happen independently by the runner OS or common telemetry endpoints.
var DomainIgnoreList = []string{
	// Also ignore _* - e.g. _https._tcp.apt.releases.hashicorp.com
	"cdn.fwupd.org",
	"fwupd.org",
	"esm.ubuntu.com",
	"motd.ubuntu.com",
	"telemetry.nextjs.org",
}

// This is a list of URIs that are needed for the agent to function in production
// See https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners#communication-requirements-for-github-hosted-runners
// For Proxima/GHE.com, see https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom
var githubBaseRequiredAllowList = []string{
	// "https://github.{{suffix}}/", <- Covered by GITHUB_SERVER_URL, so can be dynamic
	"githubusercontent.{{suffix}}", // <- Need wildcard for this domain, so don't prefix with https://
	"https://raw.githubusercontent.{{suffix}}/",
	"https://objects.githubusercontent.{{suffix}}/",
	"https://codeload.github.{{suffix}}/",
	"https://uploads.github.{{suffix}}/user-attachments/assets/",                         // <- Used to upload images to GitHub
	"https://api.github.{{suffix}}/internal/user-attachments/assets/",                    // <- Used to download user attachments from GitHub
	"https://api.github.{{suffix}}/advisories",                                           // <- Used to fetch security advisories from GitHub
	"https://api.github.{{suffix}}/copilot_internal/user",                                // <- Used by the compiler to fetch Copilot user details
	"https://api.github.{{suffix}}/repos/{{repo_owner}}/{{repo_name}}/copilot_internal/", // <- Used to access copilot embeddings index for specific repo
	"https://api.github.{{suffix}}/repos/{{repo_owner}}/{{repo_name}}/compare/",          // <- Used by the dependabot checker to list changed files via the GitHub Compare API
	"https://api.github.{{suffix}}/embeddings/code/search",                               // <- Used for embeddings code search
	"https://github.githubassets.{{suffix}}/assets",                                      // <- Used to load assets for GitHub pages, e.g.'"
	"https://*.githubusercontent.{{suffix}}",                                             // <- Used to download assets from S3
	"https://uploads.github.{{suffix}}",
	// Special IPs / domains
	"172.18.0.1",           // <- Docker default bridge network IP. We will remove this w/a firewall binary update to auto-handle
	"168.63.129.16",        // <- Azure MetaData endpoint used by WAAgent https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/agent-linux
	"host.docker.internal", // <- Docker internal host IP if set
	// Git LFS
	"https://lfs.github.com/",
	"https://github-cloud.githubusercontent.{{suffix}}/",
	"https://github-cloud.s3.amazonaws.com/",
	// GitHub tools always downloaded from GitHub.com
	"https://api.github.com/repos/github/codeql-action/releases/", // <- Used to download CodeQL CLI
	"https://api.github.com/repos/dependabot/cli/releases/",       // <- Used to download dependabot CLI
	// GitHub Actions workflow run artifact storage accounts (Azure blob storage endpoints productionresultssa0-19)
	"https://productionresultssa0.blob.core.windows.net/",
	"https://productionresultssa1.blob.core.windows.net/",
	"https://productionresultssa2.blob.core.windows.net/",
	"https://productionresultssa3.blob.core.windows.net/",
	"https://productionresultssa4.blob.core.windows.net/",
	"https://productionresultssa5.blob.core.windows.net/",
	"https://productionresultssa6.blob.core.windows.net/",
	"https://productionresultssa7.blob.core.windows.net/",
	"https://productionresultssa8.blob.core.windows.net/",
	"https://productionresultssa9.blob.core.windows.net/",
	"https://productionresultssa10.blob.core.windows.net/",
	"https://productionresultssa11.blob.core.windows.net/",
	"https://productionresultssa12.blob.core.windows.net/",
	"https://productionresultssa13.blob.core.windows.net/",
	"https://productionresultssa14.blob.core.windows.net/",
	"https://productionresultssa15.blob.core.windows.net/",
	"https://productionresultssa16.blob.core.windows.net/",
	"https://productionresultssa17.blob.core.windows.net/",
	"https://productionresultssa18.blob.core.windows.net/",
	"https://productionresultssa19.blob.core.windows.net/",
	// GitHub URLs that need to be added if we lock down the host instead of the process
	// "https://api.github.{{suffix}}/", <- Covered by GITHUB_API_URL_BASE, so can be dynamic
	// "https://*.actions.githubusercontent.{{suffix}}/",
	// "https://pkg.actions.githubusercontent.{{suffix}}/",
	// "https://results-receiver.actions.githubusercontent.{{suffix}}/",
	// "https://objects-origin.githubusercontent.{{suffix}}/"
	// "https://github-releases.githubusercontent.{{suffix}}/"
	// "https://github-registry-files.githubusercontent.{{suffix}}/"
	// "https://dependabot-actions.githubapp.{{suffix}}/" <- Should not be needed
}

// Default network rules are now controlled by the `default_network_rules` files, for example internal/config/default_network_rules/go.rules.yaml
// they contain trusted package repositories, certificate authorities, and top safe URLs from
// https://splunk.githubapp.com/en-US/app/gh_reference_app/report?s=%2FservicesNS%2Fchuxel%2540github.com%2Fgh_reference_app%2Fsaved%2Fsearches%2FCopilot%2520code%2520agent%2520top%2520blocked%2520domains

// GenerateEncodedDefaultRulesSetEnv generates a gzipped and base64-encoded string of default network rules.
func GenerateEncodedDefaultRulesSetEnv() (string, error) {
	output := strings.Builder{}
	files, err := DefaultNetworkRules.ReadDir(DefaultNetworkRulesFolder)
	if err != nil {
		return "", goerrors.Errorf("failed to read default network rules directory: %w", err)
	}
	for _, file := range files {
		fileBytes, err := DefaultNetworkRules.ReadFile(path.Join(DefaultNetworkRulesFolder, file.Name()))
		if err != nil {
			return "", goerrors.Errorf("failed to read file %s: %w", file.Name(), err)
		}

		_, _ = output.WriteString(fmt.Sprintf("\n---\n%s", fileBytes))
	}

	// Gzip and base64 encode the output
	var buf bytes.Buffer
	gzipWriter := gzip.NewWriter(&buf)
	_, err = gzipWriter.Write([]byte(output.String()))
	if err != nil {
		return "", goerrors.Errorf("failed to gzip default network rules: %w", err)
	}
	err = gzipWriter.Close()
	if err != nil {
		return "", goerrors.Errorf("failed to close gzip writer: %w", err)
	}

	// Base64 encode the gzipped content
	encoded := base64.StdEncoding.EncodeToString(buf.Bytes())
	return encoded, nil
}

// GenerateRequiredFirewallAllowList creates the minimum required firewall rules for the agent as csv
func GenerateRequiredFirewallAllowList(cfg *Config) string {
	sb := strings.Builder{}
	// Allow calls to locally running services on all ports and we will also not add
	// variations like http://localhost:<port> since a URL with a port is not supported yet.
	// But we should only see these in development, so its not a user-facing issue.
	// Note: 127.0.0.1 is on by default for firewall otherwise lots of stuff breaks
	_, _ = sb.WriteString("localhost,")

	// Add Proxima specific URLs if in Proxima environment
	if cfg.Environment == EnvironmentProxima {
		_, _ = sb.WriteString(generateProximaAllowList(cfg))
	}

	// Automatically add the GitHub server URL, API URL, and callback URLs w/o the path
	// to the allow list. This is to ensure that the agent can communicate with the server.
	baseList := strings.Join(githubBaseRequiredAllowList, ",")
	serverURL, err := url.Parse(cfg.GitHubServerURL)
	if err != nil {
		_, _ = sb.WriteString(strings.ReplaceAll(baseList, "{{suffix}}", "com"))
	} else {
		if serverURL.Hostname() != "localhost" {
			serverURL.Path = "/"
			_, _ = sb.WriteString(serverURL.String())
			_, _ = sb.WriteString(",")
		}
		// Adapt URLs when the server is localhost or github.localhost
		if serverURL.Hostname() == "github.localhost" || serverURL.Hostname() == "localhost" {
			_, _ = sb.WriteString(strings.ReplaceAll(baseList, "{{suffix}}", "localhost"))
		} else {
			// TODO: Adapt to GHE.com URLs beyond "github.com" which should be automatically handled. Most others appear to be normal .com addresses.
			_, _ = sb.WriteString(strings.ReplaceAll(baseList, "{{suffix}}", "com"))
		}
	}
	_, _ = sb.WriteString(",")

	// Add unique capiURL unless it is localhost
	capiURL, err := url.Parse(cfg.CopilotAPIURL)
	if err == nil && capiURL.Hostname() != "localhost" {
		capiURL.Path = "/"
		_, _ = sb.WriteString(capiURL.String())
		_, _ = sb.WriteString(",")
	}
	// Add unique callbackURL unless it is localhost
	callbackURL, err := url.Parse(cfg.AgentCallbackURL)
	if err == nil && callbackURL.Hostname() != "localhost" {
		callbackURL.Path = "/"
		_, _ = sb.WriteString(callbackURL.String())
		_, _ = sb.WriteString(",")
	}
	if sb.Len() > 0 {
		return sb.String()[:sb.Len()-1]
	}
	return sb.String()
}

func generateProximaAllowList(config *Config) string {
	uploadURL := "https://uploads.<tenant>.ghe.com/user-attachments/assets"        // <- Used to upload images to GitHub in Proxima
	downloadURL := "https://api.<tenant>.ghe.com/internal/user-attachments/assets" // <- Used to download user attachments from GitHub in Proxima
	copilotInternalUserURL := "https://api.<tenant>.ghe.com/copilot_internal/user" // <- Used by the compiler to fetch Copilot user details in Proxima
	secretScanningURL := config.SecretScanningURL                                  // <- Used to scan copilot-coding-agent code output using GitHub Secret Scanning
	objectsOriginURL := "https://objects-origin.<tenant>.ghe.com"                  // <- Used to download GitHub assets in Proxima
	memoryAlphaURL := config.GetMemoryAlphaURL()                                   // <- Used for large file storage in Proxima and yup, format is different
	advisoriesURL := config.GitHubAdvisoriesURL                                    // <- Used to fetch security advisories from GitHub in Proxima
	telemetryURL := "https://copilot-telemetry-service.<tenant>.ghe.com"           // <- Telemetry service used by Proxima

	return fmt.Sprintf("%s,%s,%s,%s,%s,%s,%s,%s,", uploadURL, downloadURL, copilotInternalUserURL, secretScanningURL, objectsOriginURL, memoryAlphaURL, advisoriesURL, telemetryURL)
}
