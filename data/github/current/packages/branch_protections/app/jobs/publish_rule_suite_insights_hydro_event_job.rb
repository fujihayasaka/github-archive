# typed: true
# frozen_string_literal: true

class PublishRuleSuiteInsightsHydroEventJob < ApplicationJob
  DEBOUNCE_INTERVAL = 5.minutes.to_i

  queue_as :rule_suite_insights

  retry_on ActiveJob::DeserializationError
  retry_on_dirty_exit

  sig { params(rule_suite_id: Integer, repository_id: Integer).void }
  def perform(rule_suite_id, repository_id)
    rule_suite = RuleEngine::RuleSuite.find_by(id: rule_suite_id, repository_id: repository_id)
    return unless rule_suite
    return if rule_suite.entered_queue?

    repository = rule_suite.repository
    return unless repository
    return unless FeatureFlag.vexi.enabled?(:rule_suite_insights_write, repository, repository.organization, repository.business_owner, default: false)

    GlobalInstrumenter.instrument("rule_suite.insights_publish", {
      rule_suite: rule_suite,
      repository: repository,
    })
  end
end
