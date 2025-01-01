# typed: true
# frozen_string_literal: true

class CancelPendingExemptionRequestsJob < ApplicationJob

  queue_as :cancel_pending_exemption_requests
  retry_on_dirty_exit

  RESOURCE_OWNER_ID_BATCH_SIZE = 10_000

  def perform(ruleset, rule_provider)
    resource_owner_ids = Exemptions::ExemptionRequest
        .for_source(ruleset.source)
        .where(status: :pending, resource_owner_type: "RuleEngine::RuleSuite")
        .pluck(:resource_owner_id)

    resource_owner_ids.each_slice(RESOURCE_OWNER_ID_BATCH_SIZE) do |resource_owner_id_batch|
      repository_rule_suite_ids = RuleEngine::RuleSuite
      .where(id: resource_owner_id_batch)
      .joins("
        INNER JOIN repository_rule_runs
        ON repository_rule_suites.id = repository_rule_runs.repository_rule_suite_id
        AND repository_rule_runs.rule_provider_id = #{ruleset.id}
        AND repository_rule_runs.rule_provider = '#{rule_provider}'
        AND repository_rule_suites.repository_id = repository_rule_runs.repository_id")
      .pluck("repository_rule_suites.id")
      Exemptions::ExemptionRequest.where(resource_owner_id: repository_rule_suite_ids, status: :pending).pluck(:id).each_slice(1000) do |ex_req_batch|
        with_write { Exemptions::ExemptionRequest.where(id: ex_req_batch).update_all(status: :cancelled) }
      end
    end
  end
end
