# typed: true
# frozen_string_literal: true

class Hook::Event::CheckSuiteEvent < Hook::Event
  include Hook::Event::ChecksDependency

  supports_targets(*DEFAULT_TARGETS)
  description "Check suite is requested, rerequested, or completed."

  event_attr :check_suite_id, :action, required: true
  # specific_app_only lets us send this hook to a specific app instead of any app subscribed to these events
  event_attr :specific_app_only, :actor_id, :actions_meta

  def check_suite
    record_query_counts "prehydration_check_suite_queries" do
      @check_suite ||= CheckSuite.find(check_suite_id)
    end
  end

  def deliverable?
    check_suite && !target_repository.nil? && target_repository.commits.exist?(check_suite.head_sha)
  end

  def filterable_for_actions?
    return false unless target_repository.present?

    # Rerequested check suites are used for re-runs and should not be filtered out
    action.to_sym != :rerequested
  end

  def initialize_primary_resource
    return unless super
    # explicit column filtering to ensure even model is resilient to migrations and database changes
    # https://github.com/github/availability/issues/2669
    valid_keys = CheckSuite.column_names
    primary_resource_data.filter! do |key|
      valid_keys.any? { |valid_key| key.to_s == valid_key }
    end
    @check_suite = CheckSuite.new(primary_resource_data)
  end
end
