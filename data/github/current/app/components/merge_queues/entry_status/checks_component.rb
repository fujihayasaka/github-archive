# typed: true
# frozen_string_literal: true

class MergeQueues::EntryStatus::ChecksComponent < ApplicationComponent
  include GitHub::Memoizer
  include PullRequests::External::Domain::StatusChecks::Provider

  # entry - a MergeQueueEntry
  sig { params(entry: MergeQueueEntry, blocked: T::Boolean, repository: T.nilable(Repository)).void }
  def initialize(entry:, blocked: false, repository: nil)
    @entry = entry
    @blocked = blocked
    @repository = repository
  end

  def call
    render MergeQueues::EntryStatus::DetailComponent.new(
      summary_color: summary_color,
      summary: summary,
      details: details,
      test_selector_prefix: "checks-status",
      check_runs_list: status_checks,
    )
  end

  private

  sig { returns(MergeQueueEntry) }
  attr_reader :entry

  sig { returns(T::Boolean) }
  def show_all_checks?
    @repository&.feature_flag_enabled?(:merge_queue_show_non_required_checks, default: false) == true
  end

  sig { returns(T::Array[PullRequests::External::Domain::StatusChecks::IStatusCheck]) }
  memoize def status_checks
    if show_all_checks?
      status_checks_domain
        .for_merge_queue_entry(entry)
        .sort_by { _1.required? ? 0 : 1 } # Show required at the top.
    else
      status_checks_domain
        .for_merge_queue_entry(entry)
        .filter(&:required?)
    end
  end

  sig { returns(T::Boolean) }
  def blocked?
    @blocked
  end

  sig { returns(T::Boolean) }
  def render?
    !blocked? && status_checks.present?
  end

  sig { returns(Symbol) }
  def summary_color
    if entry.required_status_success?
      :success
    elsif entry.required_status_pending?
      :attention
    else
      :danger
    end
  end

  sig { returns(String) }
  def summary
    if entry.required_status_success?
      "All required checks have passed"
    elsif entry.required_status_pending?
      "Some required checks haven't completed yet"
    else
      "Some required checks were not successful"
    end
  end

  sig { returns(String) }
  memoize def details
    counts_with_state = if show_all_checks?
      status_checks.filter(&:required?).group_by(&:state).map do |state, check_runs|
        "#{check_runs.count} #{StatusCheckConfig.adjective_state(state)}"
      end
    else
      status_checks.group_by(&:state).map do |state, check_runs|
        "#{check_runs.count} #{StatusCheckConfig.adjective_state(state)}"
      end
    end

    "#{counts_with_state.to_sentence} required check".pluralize(status_checks.count) + "."
  end
end
