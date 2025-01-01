# typed: true
# frozen_string_literal: true

# This job is responsible for ensuring that all alerts on a repository are up-to-date after custom rules are enabled,
# disabled, or deleted. By finding the alerts that match rule change criteria and calling `auto_dismiss_or_reopen`
# on each of them, we ensure that each affected alert either gets re-opened or remains auto-dismissed by another rule.
class ReprocessAlertRulesJob < ApplicationJob
  queue_as :vulnerability_identification

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RuleNotYetDeleted = Class.new(StandardError)

  retry_on RuleNotYetDeleted, wait: :polynomially_longer, attempts: 10 do |job, error|
    GitHub.logger.info(
      "Job failed because Rule with id #{job.arguments.first[:rule_id]} has not yet been deleted.",
      "code.namespace": self.class.name,
      "gh.security_alerts.exception.type": error.class.name,
      "gh.security_alerts.attempt.number": job.executions,
    )

    raise RuleNotYetDeleted
  end

  def perform(repository_id:, enabled_rule_ids: nil, disabled_rule_ids: nil, deleted_rule_id: nil, created_rule_id: nil, edited_rule_id: nil)
    raise ArgumentError, "Missing at least one required argument: enabled_rule_ids, disabled_rule_ids, deleted_rule_id, created_rule_id, edited_rule_id" \
      if enabled_rule_ids.nil? && disabled_rule_ids.nil? && deleted_rule_id.nil? && created_rule_id.nil? && edited_rule_id.nil?
    @repository_id = repository_id
    @pull_request_candidates = Set.new

    if deleted_rule_id.present?
      raise RuleNotYetDeleted if VulnerabilityAlertRule.where(id: deleted_rule_id, state: "active").present?

      # When deleting an existing rule, we'll limit our search to alerts currently affected by the rule:
      alert_scope = RepositoryVulnerabilityAlert.where(repository_id:, last_state_change_rule_id: deleted_rule_id)
      process_alerts!(alert_scope, :previous_rule_deleted)

      activity_manager.on_delete(deleted_rule_id)
    end

    if disabled_rule_ids.present?
      # When disabling an existing rule, we'll limit our search to alerts currently affected by the rule:
      alert_scope = RepositoryVulnerabilityAlert.where(repository_id:, last_state_change_rule_id: disabled_rule_ids)
      process_alerts!(alert_scope, :previous_rule_disabled)

      activity_manager.on_disable(disabled_rule_ids)
    end

    if enabled_rule_ids.present?
      # In the case of enabling a new rule, we want to look at ALL open alerts because they might be applicable:
      alert_scope = RepositoryVulnerabilityAlert.where(repository_id:, state: :open)
      process_alerts!(alert_scope, :rule_enabled)

      activity_manager.on_enable(enabled_rule_ids)
    end

    if created_rule_id.present?
      # In the case of creating a new rule, we want to look at ALL open alerts because they might be applicable:
      alert_scope = RepositoryVulnerabilityAlert.where(repository_id:, state: :open)
      process_alerts!(alert_scope, :rule_created)

      activity_manager.on_create(created_rule_id)
    end

    if edited_rule_id.present?
      # When editing a rule, we want to look at ALL open alerts and alerts currently auto_dismissed by the rule:
      alert_scope = RepositoryVulnerabilityAlert.where(repository_id:, last_state_change_rule_id: edited_rule_id)
      process_alerts!(alert_scope, :previous_rule_updated)

      alert_scope = RepositoryVulnerabilityAlert.where(repository_id:, state: :open)
      process_alerts!(alert_scope, :rule_updated)

      activity_manager.on_update(edited_rule_id)
    end

    @pull_request_candidates.each do |alert|
      Dependabot::RepositoryVulnerabilityCreatedJob.enqueue(alert)

      GitHub.logger.info(
        "code.namespace": self.class.name,
        "code.function": "perform",
        "gh.repo.id": @repository_id,
        "gh.security_alerts.job.reprocess_alert_rules.pr_candidate": alert.id,
      )
    end
  end

  def process_alerts!(scope, reason)
    changed, attempted = 0, 0

    scope.find_each do |alert|
      attempted += 1

      if alert.auto_dismiss_or_reopen(reason:)
        changed += 1
      end

      if alert.candidate_for_pull_request?
        @pull_request_candidates << alert
      end
    end

    GitHub.logger.info(
      "code.namespace": self.class.name,
      "code.function": "process_alerts!",
      "gh.repo.id": @repository_id,
      "gh.security_alerts.job.reprocess_alert_rules.attempted": attempted,
      "gh.security_alerts.job.reprocess_alert_rules.changed": changed,
      "gh.security_alerts.job.reprocess_alert_rules.reason": reason,
      "gh.security_alerts.job.reprocess_alert_rules.pr_candidates": @pull_request_candidates.count,
    )
  end

  def activity_manager
    return @activity_manager if defined?(@activity_manager)

    repository = Repositories::Public.find_active!(@repository_id)
    @activity_manager = DependabotVulnerabilityAlertRulesActivityManager.new(repository)
  end
end
