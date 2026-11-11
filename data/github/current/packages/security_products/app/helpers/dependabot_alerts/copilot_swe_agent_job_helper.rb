# typed: strict
# frozen_string_literal: true

# Helper methods for generating problem statements and PR data for Copilot SWE Agent (sweagentd)
# sessions created from Dependabot vulnerability alerts.
#
# Based on the patterns in CopilotSweAgentJobHelper (packages/issues) but adapted
# for alert-specific data (advisory details, vulnerability info, package/ecosystem data).
#
# Unlike the issue-based helper, alerts don't have user comment threads,
# so the problem statement is built purely from advisory/vulnerability metadata.
module DependabotAlerts
  module CopilotSweAgentJobHelper
    MAX_PROBLEM_STATEMENT_BASE64_LENGTH = 40_000 # ~30,000 characters
    SECTION_SEPARATOR = "----\n"
    ALERT_SECTION_HEADER = "*This section details the Dependabot vulnerability alert you should resolve*"

    # Main entry point for generating a problem statement from a Dependabot alert.
    #
    # Returns a Hash with :statement (String) and :truncation_info (Hash)
    sig do
      params(
        alert: RepositoryVulnerabilityAlert,
        agent_instructions: T.nilable(String),
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def self.generate_alert_problem_statement(alert:, agent_instructions: nil)
      truncation_info = {
        description_truncated: T.let(false, T::Boolean),
      }

      # Try with full content first
      statement = build_statement(alert, agent_instructions, 0)
      if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
        return { statement: statement, truncation_info: truncation_info }
      end

      # Progressively truncate description
      truncation_info[:description_truncated] = true
      max_description_length = approximate_max_description_length(alert, agent_instructions)
      while max_description_length > 0
        statement = build_statement(alert, agent_instructions, max_description_length)
        if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
          return { statement: statement, truncation_info: truncation_info }
        end
        max_description_length -= 500
      end

      # Last resort: minimal description
      statement = build_statement(alert, agent_instructions, 1)
      if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
        return { statement: statement, truncation_info: truncation_info }
      end

      raise "Failed to generate problem statement within size limits"
    end

    # Generate PR data for an alert assignment.
    #
    # Returns a Hash with :title, :body_placeholder, and :body_suffix
    sig do
      params(
        alert: RepositoryVulnerabilityAlert,
      ).returns(T::Hash[Symbol, String])
    end
    def self.generate_pr_data(alert:)
      repo = alert.repository
      body_placeholder = "Thanks for assigning this alert to me. I'm starting to work on it and will keep this PR's description up to date as I form a plan and make progress."

      nwo = repo ? repo.name_with_display_owner : ""
      body_suffix = "- Resolves #{nwo} alert ##{alert.number}"

      {
        title: alert.title,
        body_placeholder: body_placeholder,
        body_suffix: body_suffix,
      }
    end

    # Private helpers

    # XML structure to enable _easier_ parsing by LLM agent and to support progressive truncation
    #   This pattern was borrowed from Issues implementation - packages/issues/app/helpers/copilot_swe_agent_job_helper.rb
    sig { params(alert: RepositoryVulnerabilityAlert, agent_instructions: T.nilable(String), max_description_length: Integer).returns(String) }
    def self.build_statement(alert, agent_instructions, max_description_length)
      vuln = alert.vulnerability
      vvr = alert.vulnerable_version_range

      xml = []
      xml << ""
      xml << SECTION_SEPARATOR
      xml << ALERT_SECTION_HEADER
      xml << ""

      # Title / summary
      xml << xml_tag("alert_title", alert.title)

      # Advisory description
      description = vuln&.description
      xml << xml_tag("alert_description", truncate(description, max_description_length))
      xml << ""

      # Severity
      xml << xml_tag("severity", alert.severity)

      # Identifiers (GHSA, CVE)
      identifiers = []
      if vuln
        identifiers << vuln.ghsa_id if vuln.ghsa_id.present?
        identifiers << vuln.cve_id if vuln.cve_id.present?
      end
      xml << xml_tag("identifiers", identifiers.join(", ")) if identifiers.any?

      # Package and ecosystem
      xml << xml_tag("package", alert.package_name)
      xml << xml_tag("ecosystem", alert.ecosystem)

      # Version information
      xml << xml_tag("vulnerable_versions", alert.vulnerable_requirements)
      xml << xml_tag("patched_version", vvr&.fixed_in)

      # Manifest path
      xml << xml_tag("manifest_path", alert.vulnerable_manifest_path)
      xml << ""

      # References
      reference_urls = vuln&.reference_urls
      if reference_urls.present?
        xml << "<references>"
        reference_urls.each do |url|
          xml << xml_tag("url", url)
        end
        xml << "</references>"
        xml << ""
      end

      # Agent instructions
      if agent_instructions.present?
        xml << xml_tag("agent_instructions", agent_instructions)
        xml << ""
      end

      # Task instructions for how to resolve the alert
      xml << xml_tag("task_instructions",
        "Resolve this alert by updating the affected package to a non-vulnerable version. " \
        "Prefer the lowest non-vulnerable version (see the patched_version field above) over the latest to minimize breaking changes. " \
        "Include a Reachability Assessment section in the PR description. Review the alert_description field to understand which APIs, features, or configurations are affected, then search the codebase for usage of those specific items. " \
        "If the vulnerable code path is reachable, explain how (which files, APIs, or call sites use the affected functionality) and note that the codebase is actively exposed to this vulnerability. " \
        "If the vulnerable code path is not reachable, explain why (e.g. the affected API is never called, the vulnerable configuration is not used) and note that the update is primarily to satisfy vulnerability scanners rather than to address an active risk. " \
        "If the advisory is too vague to determine reachability (e.g. 'improper input validation' with no specific API named), state that reachability could not be determined and explain why. " \
        "Include a confidence level in the reachability assessment (e.g. high confidence if the advisory names a specific API and you confirmed it is or is not called, low confidence if the usage is indirect and hard to trace). " \
        "If no patched version is available, check the alert_description field for a Workarounds section — the advisory may describe configuration changes or usage patterns that mitigate the vulnerability without a version update. " \
        "If a workaround is available, apply it and leave a code comment referencing the advisory identifier explaining it is a temporary mitigation. " \
        "If neither a patch nor a workaround is available, explain in the PR description why the alert cannot be resolved automatically so a human reviewer can take over. " \
        "Inspect the repository to determine which package manager is used (e.g. lock files, config files, build scripts) and use that tooling to perform the update — do not edit lock files directly. " \
        "If the version constraint in the manifest (e.g. package.json, Gemfile, pyproject.toml) caps the version below the fix, update the constraint first. " \
        "For transitive dependencies, determine whether it is simpler to update the direct dependency that pulls in the vulnerable package or to update the transitive dependency directly, and choose the least disruptive approach. " \
        "If upgrading to fix the vulnerability forces a major version bump or known breaking changes, review the changelog or release notes, then audit the codebase for usage of affected APIs and fix any breaking changes that are found. " \
        "If the package manager fails to resolve dependencies (e.g. peer dependency conflicts, incompatible engine constraints), document the error in the PR description rather than attempting increasingly complex workarounds. " \
        "After updating, check the lock file to confirm the package no longer resolves to a version in the vulnerable range. " \
        "Keep changes minimal and tightly scoped. " \
        "Ensure tests, build, type checking, and linting all pass after your changes. " \
        "If there are any test, lint, or typechecking failures, investigate whether they are caused by the update and fix them if so — do not leave broken tests in the PR. If they were already present before the update, note them in the PR description so a human reviewer can assess whether they are related.")
      xml << ""

      xml.join("\n")
    end

    sig { params(tag: String, content: T.nilable(String)).returns(String) }
    def self.xml_tag(tag, content)
      "<#{tag}>#{content}</#{tag}>"
    end

    sig { params(str: T.nilable(String), max_length: T.nilable(Integer)).returns(T.nilable(String)) }
    def self.truncate(str, max_length)
      return str if max_length.nil? || max_length <= 0 || str.nil? || str.length <= max_length
      (max_length > 3) ? "#{str[0...(max_length - 3)]}..." : str[0...max_length]
    end

    sig { params(str: String).returns(Integer) }
    def self.base64_length(str)
      [str].pack("m0").length
    end

    sig { params(alert: RepositoryVulnerabilityAlert, agent_instructions: T.nilable(String)).returns(Integer) }
    def self.approximate_max_description_length(alert, agent_instructions)
      # Build statement with empty description to estimate overhead
      overhead_statement = build_statement(alert, agent_instructions, 1)
      overhead = overhead_statement.length
      [(MAX_PROBLEM_STATEMENT_BASE64_LENGTH * 0.75).to_i - overhead, 0].max
    end

    private_class_method :build_statement, :xml_tag, :truncate, :base64_length, :approximate_max_description_length
  end
end
