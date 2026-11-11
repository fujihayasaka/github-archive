# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("rule_suite.evaluate") do |payload|
    result = if payload[:result] == "stack_merge_failed" # temp until we add this to the hydro schema
      :FAILED
    elsif RuleEngine::RuleSuite::RESULTS.include?(payload[:result])
      payload[:result].upcase.to_sym
    else
      :RESULT_UNKNOWN
    end

    message = {
      rule_suite_id: payload[:id],
      user: payload[:actor].is_a?(PublicKey) ? nil : serializer.user(payload[:actor]),
      public_key: payload[:actor].is_a?(PublicKey) ? serializer.public_key(payload[:actor]) : nil,
      repository: serializer.repository(payload[:repository]),
      before_oid: payload[:before_oid],
      after_oid: payload[:after_oid],
      policy_oid: payload[:policy_oid],
      ref_name: payload[:ref_name]&.force_encoding("UTF-8")&.scrub,
      result: result,
      rule_runs: payload[:rule_runs].map { |rule_run| serializer.rule_run(rule_run) }
    }

    publish(message, schema: "github.repositories.v1.RuleSuiteEvaluation")
  end
end

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("rule_suite.evaluate") do |payload|
    next if GitHub.enterprise?

    next unless payload[:result_changed]
    next if payload[:result] == "entered_queue"

    # Match the Rule Insights page: only process ref-level operations (push/branch/tag),
    # not repository policy operations (delete, rename, visibility, transfer).
    next if payload[:event_action_type] == RuleEngine::EventActionRepositoryOperation.name

    repository = payload[:repository]
    next unless FeatureFlag.vexi.enabled?(:rule_suite_insights_write, repository, repository.organization, repository.business_owner, default: false)

    # Debounce: schedule a delayed job instead of publishing inline.
    # Push events cause RuleSuites to be saved multiple times (quarantine pre-receive, then
    # post-receive merge). Ensure we only publish one hydro event
    # per suite, reading the settled DB state after the debounce window expires.

    context_key = "rule_suite_insights_enqueued:#{payload[:id]}:#{repository.id}"
    next if GitHub.context[context_key]

    GitHub.context.push(context_key => true)
    PublishRuleSuiteInsightsHydroEventJob
    .set(wait: PublishRuleSuiteInsightsHydroEventJob::DEBOUNCE_INTERVAL)
    .perform_later(payload[:id], repository.id)
  end
end

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  def result_enum(serializer, value)
    serializer.enum(
      type: Hydro::Schemas::Github::RulesInsights::V0::RuleSuiteEvaluation::Result,
      value: value,
      default: :RESULT_UNKNOWN
    )
  end

  subscribe("rule_suite.insights_publish") do |payload|
    rule_suite = payload[:rule_suite]
    data = rule_suite.to_rules_insights_dashboard_doc

    message = {
      rule_suite_id: data[:suite_id],
      business_id: data[:business_id],
      org_id: data[:org_id],
      repo_id: data[:repo_id],
      created_at: Google::Protobuf::Timestamp.new(seconds: data[:created_at].to_i, nanos: 0),
      actor_id: data[:actor_id],
      actor_type: data[:actor_type],
      suite_result: result_enum(serializer, data[:suite_result]),
      result_active_repo: result_enum(serializer, data[:result_active_repo]),
      result_active_org: result_enum(serializer, data[:result_active_org]),
      result_active_business: result_enum(serializer, data[:result_active_business]),
      result_evaluate_repo: result_enum(serializer, data[:result_evaluate_repo]),
      result_evaluate_org: result_enum(serializer, data[:result_evaluate_org]),
      result_evaluate_business: result_enum(serializer, data[:result_evaluate_business]),
      result_all_repo: result_enum(serializer, data[:result_all_repo]),
      result_all_org: result_enum(serializer, data[:result_all_org]),
      result_all_business: result_enum(serializer, data[:result_all_business]),
    }

    publish(message, schema: "github.rules_insights.v0.RuleSuiteEvaluation")
  end
end
