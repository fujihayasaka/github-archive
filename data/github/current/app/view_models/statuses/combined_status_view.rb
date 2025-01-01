# typed: true
# frozen_string_literal: true

class Statuses::CombinedStatusView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include StatusHelper
  attr_reader :combined_status, :simple_view, :commit, :required_status_decision_basis_commit, :popover

  # Optional PullRequest context used on merge form
  attr_reader :pull

  # Statuses sorted by state
  def statuses
    @statuses ||= begin
      combined_status.prefill
      combined_status.status_checks.sort_by(&:sort_order)
    end
  end

  def status_counts_by_context
    statuses.inject(Hash.new(0)) do |res, status|
      res[status.state] += 1
      res
    end
  end

  def all_succeeded?
    if statuses.empty?
      return StatusCheckConfig::SUCCESS_STATES.include?(combined_status.state)
    end
    statuses.all? { |s| StatusCheckConfig::SUCCESS_STATES.include?(s.state) }
  end

  def all_failing?
    statuses.all? { |s| StatusCheckConfig::FAILURE_STATES.include?(s.state) } unless statuses.empty?
  end

  def any_failing?
    statuses.any? { |s| StatusCheckConfig::FAILURE_STATES.include?(s.state) } unless statuses.empty?
  end

  def all_pending?
    statuses.all? { |s| StatusCheckConfig::PENDING_STATES.include?(s.state) } unless statuses.empty?
  end

  def any_pending?
    statuses.any? { |s| StatusCheckConfig::PENDING_STATES.include?(s.state) } unless statuses.empty?
  end

  def is_deleted?
    statuses.empty?
  end

  def list_checks?
    statuses.any? { |status| status.state != "success" }
  end

  def pending?
    StatusCheckConfig::PENDING_STATES.include?(state)
  end

  def state
    combined_status.state
  end

  def render_show_hide_checks_button?
    !simple_view
  end

  def checks_status_summary(check_name = "check")
    if combined_status.status_checks.empty?
      # we don't want to display any summary text for the popover message
      return if popover
      # in other cases, we want to display the short text message for rollups
      return combined_status.short_text
    end

    counts = statuses
    .group_by { |status| StatusCheckConfig.adjective_state(status.state) }
    .map { |state, statuses| "#{statuses.length} #{state}" }

    "#{counts.to_sentence} #{check_name}".pluralize(statuses.length)
  end

  def retention_message
    return nil if !popover
    return combined_status.rollup_archive_message unless combined_status.status_checks.empty?
    combined_status.rollup_deleted_message
  end

  def status_required?(status)
    return @status_required[status] if defined?(@status_required)

    @status_required = if pull
      Promise.all(statuses.map do |status|
        status.async_required_for_pull_request?(pull).then do |is_required|
          [status, is_required]
        end
      end).sync.to_h
    else
      {}.tap { |hash| hash.default = false }
    end

    @status_required[status]
  end

  def graphql?
    false
  end

  def workflows_pending_approval?
    return false unless pull.present?
    action_required_check_suites.any?
  end

  def action_required_check_suites
    @action_required_check_suites ||= pull.action_required_check_suites(head_sha: pull.head_sha)
  end

  def sorted_statuses
    # 'true' comes after 'false' in lexical sort order, but we want to show
    # things that evaluate to 'true' first. hopefully variables make this clearer
    first = 0
    second = 1
    statuses.sort_by do |s|
      [
        StatusCheckConfig::FAILURE_STATES.include?(s.state) ? first : second,
        StatusCheckConfig::PENDING_STATES.include?(s.state) ? first : second,
        StatusCheckConfig::INCOMPLETE_STATES.include?(s.state) ? first : second,
        StatusCheckConfig::SUCCESS_STATES.include?(s.state) ? first : second,
      ]
    end
  end
end
