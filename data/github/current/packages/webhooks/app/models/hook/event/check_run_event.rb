# typed: true
# frozen_string_literal: true

class Hook::Event::CheckRunEvent < Hook::Event
  include Hook::Event::ChecksDependency

  supports_targets(*DEFAULT_TARGETS)
  description "Check run is created, requested, rerequested, or completed."

  event_attr :check_run_id, :action, required: true
  # specific_app_only lets us send this hook to a specific app instead of any app subscribed to these events
  event_attr :specific_app_only, :actor_id, :requested_action

  def check_run
    record_query_counts "prehydration_check_run_event_queries" do
      @check_run ||= begin
        run = Checks.domain.check_runs.unsafe_for_id(check_run_id)
        raise ActiveRecord::RecordNotFound unless run
        run
      end
    end
  end

  def check_suite
    @check_suite ||= check_run.check_suite
  end

  def initialize_primary_resource
    # explicit column filtering to ensure even model is resilient to migrations and database changes
    # https://github.com/github/availability/issues/2669
    return unless super
    valid_keys = CheckRun.column_names
    primary_resource_data.filter! do |key|
      valid_keys.any? { |valid_key| key.to_s == valid_key }
    end
    @check_run = CheckRun.new(primary_resource_data)
  end
end
