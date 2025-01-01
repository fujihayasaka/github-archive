# typed: true
# frozen_string_literal: true

class ReprocessOrganizationAlertRulesJob < ApplicationJob
  STATS_PREFIX = "reprocess_organization_alert_rules_job"

  queue_as :vulnerability_identification

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  attr_reader :organization_id, :rule

  VALID_ACTIONS = [:enabled, :disabled, :deleted, :created, :edited]
  VALID_TARGET_TYPES = %w[User global]

  sig { params(organization_id: Integer, rule_id: Integer, action: Symbol, rule_target_type: String).void }
  def perform(organization_id:, rule_id:, action:, rule_target_type: "User")
    raise ArgumentError, "Action is invalid, must be one of #{VALID_ACTIONS}" unless action.in?(VALID_ACTIONS)
    raise ArgumentError, "rule_target_type is invalid, must be one of #{VALID_TARGET_TYPES}" unless rule_target_type.in?(VALID_TARGET_TYPES)

    @organization_id = organization_id
    @rule =
      if rule_target_type == "User"
        VulnerabilityAlertRule.find_by(target_type: "User", target_id: organization_id, id: rule_id)
      else
        VulnerabilityAlertRule.default_auto_dismissal_rule
      end

    # Iterate over all active repos in the organization to collect actionable IDs.
    actionable_repository_ids = filter_repositories_by_rule(find_repository_ids_with_alerts)

    base_job_kwargs = case action
    when :created then { created_rule_id: rule_id }
    when :deleted then { deleted_rule_id: rule_id }
    when :disabled then { disabled_rule_ids: [rule_id] }
    when :edited then { edited_rule_id: rule_id }
    when :enabled then { enabled_rule_ids: rule_id }
    end

    actionable_repository_ids.each do |repo_id|
      job_kwargs = T.must(base_job_kwargs).merge({ repository_id: repo_id })

      ReprocessAlertRulesJob.perform_later(**T.unsafe(job_kwargs))
    end
  end

  sig { returns(T::Array[Integer]) }
  def find_repository_ids_with_alerts
    repository_ids = []

    Repository.where(active: true, organization_id:).find_each do |repo|
      # If the repository isn't eligible for custom rules, skip it:
      next unless repo.dependabot_custom_rules_writable?

      # If the repository does not have any alerts associated, skip it:
      next unless repo.repository_vulnerability_alerts.count > 0

      repository_ids << repo.id
    end

    repository_ids
  end

  sig { params(repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def filter_repositories_by_rule(repository_ids)
    GitHub.dogstats.distribution_time("#{STATS_PREFIX}.filter_repositories_by_rule.time") do
      filtered_ids = []

      repository_ids.each_slice(100) do |id_batch|
        arel = RepositoryVulnerabilityAlert
          .use_index("index_repository_vulnerability_alerts_on_repository_id_and_state")
          .annotate("cross-schema-domain-query-exempted")
          .where(repository_id: id_batch)

        @rule.conditions.each do |key, value|
          case key
          when "cwe"
            arel = arel
              .joins(vulnerability: :cwes)
              .where(vulnerability: { cwes: { cwe_id: value } })
          when "scope"
            arel = arel.where(dependency_scope: value)
          when "ecosystem"
            arel = arel
              .joins(:vulnerable_version_range)
              .where(vulnerable_version_range: { ecosystem: value })
          when "package"
            arel = arel
              .joins(:vulnerable_version_range)
              .where(vulnerable_version_range: { affects: value })
          when "severity"
            arel = arel
              .joins(:vulnerability)
              .where(vulnerability: { severity: value })
          when "cve_id"
            arel = arel
              .joins(:vulnerability)
              .where(vulnerability: { cve_id: value })
          when "ghsa_id"
            arel = arel
              .joins(:vulnerability)
              .where(vulnerability: { ghsa_id: value })
          when "epss"
            value.each do |epss_condition|
              if epss_condition =~ RepositoryVulnerabilityAlert::EPSS_OPERATOR_REGEX
                operator, threshold = $1, $2.to_f
                arel = arel.joins(vulnerability: :cve_epss)
                           .where("cve_epss.percentage #{operator} ?", threshold)
              else
                raise ArgumentError, "Invalid EPSS condition format: #{epss_condition}"
              end
            end
          else
            raise ArgumentError, "Unexpected VulnerabilityAlertRule condition, please update this method to support all conditions."
          end
        end

        filtered_ids << arel.distinct.pluck(:repository_id)
      end

      results = filtered_ids.flatten

      GitHub.logger.info(
        "Filter repo IDs results",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "gh.org.id": organization_id,
        "gh.security_alerts.filter_repositories_by_rule.before_count": repository_ids.count,
        "gh.security_alerts.filter_repositories_by_rule.after_count": results.count,
      )

      results
    end
  end
end
