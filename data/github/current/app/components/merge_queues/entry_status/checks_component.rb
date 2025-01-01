# typed: true
# frozen_string_literal: true

class MergeQueues::EntryStatus::ChecksComponent < ApplicationComponent
  # entry - a MergeQueueEntry
  # required_status_checks - an Array of either RequiredStatusCheck, Status, or CombinedStatus::CheckRunAdapter
  def initialize(entry:, required_status_checks:, blocked: false)
    @entry = entry
    @required_status_checks = required_status_checks
    @blocked = blocked
  end

  def call
    render MergeQueues::EntryStatus::DetailComponent.new(
      summary_color: summary_color,
      summary: summary,
      details: details,
      test_selector_prefix: "checks-status",
      check_runs_list: required_status_checks,
    )
  end

  private

  attr_reader :entry, :required_status_checks, :blocked

  def blocked?
    @blocked
  end

  def render?
    required_status_checks.present? && !blocked?
  end

  def summary_color
    if entry.required_status_success?
      :success
    elsif entry.required_status_pending?
      :attention
    else
      :danger
    end
  end

  def summary
    if entry.required_status_success?
      "All required checks have passed"
    elsif entry.required_status_pending?
      "Some required checks haven't completed yet"
    else
      "Some required checks were not successful"
    end
  end

  memoize def details
    counts_with_state = required_status_checks.
      group_by(&:state).
      map do |state, check_runs|
        "#{check_runs.count} #{StatusCheckConfig.adjective_state(state)}"
      end

    "#{counts_with_state.to_sentence} required check".pluralize(required_status_checks.count) + "."
  end
end
