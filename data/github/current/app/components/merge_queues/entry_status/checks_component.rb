# typed: true
# frozen_string_literal: true

class MergeQueues::EntryStatus::ChecksComponent < ApplicationComponent
  include GitHub::Memoizer
  include PullRequests::External::Domain::StatusChecks::Provider

  # entry - a MergeQueueEntry
  def initialize(entry:, blocked: false)
    @entry = entry
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

  attr_reader :entry

  memoize def required_status_checks
    status_checks_domain
      .for_merge_queue_entry(entry)
      .filter(&:required?)
  end

  def blocked?
    @blocked
  end

  def render?
    !blocked? && required_status_checks.present?
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
