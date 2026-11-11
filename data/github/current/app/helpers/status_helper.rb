# typed: true
# frozen_string_literal: true

module StatusHelper
  include Kernel
  include OcticonsHelper

  def icon_or_progress_spinner_for(opts = {})
    state = opts.fetch(:state).downcase
    if state == StatusCheckConfig::IN_PROGRESS
      T.unsafe(self).render partial: "statuses/status_check_in_progress", locals: { size: 16 }
    else
      octicon(icon_symbol_for_state(state), class: opts.fetch(:class, ""))
    end
  end

  def icon_symbol_for_state(state)
    # override the default here for ACTION_REQUIRED, which is normally an 'alert'
    # The StatusCheckConfig keeps a normative definition of all the icons/colors/ect
    # But in some places we need to overide these app wide defaults.
    return "x" if state == StatusCheckConfig::ACTION_REQUIRED
    # overriding for the corner case of a commit rollup when there are too many checks to determine the state
    return "skip" if state == "too_many"

    StatusCheckConfig.for(state)&.icon
  end

  # used to color the icons
  def status_state_text_class(state)
    StatusCheckConfig.for(state)&.status_icon_color_class
  end

  # used to build the primer_octicon component
  def status_state_octicon_arguments(state)
    case state.to_s.downcase
    when StatusCheckConfig::NEUTRAL
      { icon: icon_symbol_for_state(state), classes: status_state_text_class(state) }
    when StatusCheckConfig::CANCELLED
      { icon: icon_symbol_for_state(state), classes: status_state_text_class(state) }
    when StatusCheckConfig::STALE
      { icon: icon_symbol_for_state(state), classes: status_state_text_class(state) }
    when StatusCheckConfig::SKIPPED
      { icon: icon_symbol_for_state(state), classes: status_state_text_class(state) }
    when StatusCheckConfig::SUCCESS
      { icon: icon_symbol_for_state(state), color: :success }
    when *StatusCheckConfig::FAILURE_STATES
      { icon: icon_symbol_for_state(state), color: :danger }
    when *StatusCheckConfig::INCOMPLETE_STATES
      { icon: icon_symbol_for_state(state), color: :danger }
    when *StatusCheckConfig::PENDING_STATES
      { icon: icon_symbol_for_state(state), classes: "hx_dot-fill-pending-icon" }
    when "expected"
      { icon: icon_symbol_for_state(state), classes: "hx_dot-fill-pending-icon" }
    when "too_many"
      { icon: icon_symbol_for_state(state) }
    end
  end

  # used to color the text
  def status_state_text_color(state)
    StatusCheckConfig.for(state)&.status_sentence_color_class
  end

  def additional_status_check_context(state, duration_in_seconds)
    status_check_config = StatusCheckConfig.for(state)
    if status_check_config&.pending?
      status_check_config.adjective.capitalize
    else
      time_to_complete(state, duration_in_seconds).capitalize
    end
  end

  # Provides the full additional context for a status check, including timing information
  # based on the current state.
  #
  # state - The state of the status check
  # duration_in_seconds - How long the check took or has been running
  # state_changed_at - When the state last changed (Time object)
  #
  # Returns String with additional context.
  def status_check_additional_context(state, duration_in_seconds, state_changed_at)
    if state == StatusCheckConfig::IN_PROGRESS
      "Started #{duration((Time.now - state_changed_at).floor)} ago"
    elsif state == StatusCheckConfig::QUEUED || state == StatusCheckConfig::PENDING
      "Waiting for status to be reported"
    else
      additional_status_check_context(state, duration_in_seconds)
    end
  end

  # Returns the target URL for a status check, handling different status check types.
  #
  # status - The status check object (can be various types)
  # pull_request - The pull request (optional, can be nil)
  #
  # Returns String URL or nil.
  def status_check_target_url(status, pull_request = nil)
    case status
    when PullRequests::External::Domain::StatusChecks::IStatusCheck
      pull_request ? status.target_url(pull_request) : nil
    when CombinedStatus::CheckRunAdapter
      status.target_url(pull: pull_request)
    when RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType
      pull_request ? status.target_url(pull_request_number: pull_request.number) : nil
    else
      status.target_url
    end
  end

  # Returns the avatar URL for a status check, handling different status check types.
  #
  # status - The status check object (can be various types)
  # size - The desired avatar size (default: 40)
  #
  # Returns String URL or nil.
  def status_check_avatar_url(status, size: 40)
    if status.is_a?(PullRequests::External::Domain::StatusChecks::IStatusCheck)
      return status.avatar_url(size)
    end

    if application = status.application
      application.preferred_avatar_url(size: size)
    elsif creator = status.creator
      creator.primary_avatar_url(size)
    elsif integration = status.integration # for InMemoryRequiredStatusCheck
      integration.bot&.primary_avatar_url(size)
    else
      nil
    end
  end

  # Returns the job ID for a status check if it's eligible for Copilot failure analysis.
  #
  # status - The status check object (can be various types)
  #
  # Returns Integer job_id or nil.
  def status_check_copilot_failure_job_id(status)
    check_run =
      case status
      when CombinedStatus::CheckRunAdapter
        status
      when PullRequests::External::Domain::StatusChecks::IStatusCheck
        status.as_check_run
      else
        nil
      end

    return nil unless check_run&.eligible_for_copilot_failure_analysis?
    T.must(check_run.id).to_i
  end

  def default_status_check_description(state)
    case state.downcase
    when StatusCheckConfig::IN_PROGRESS
      "This check has started..."
    when StatusCheckConfig::QUEUED
      "Waiting to run this check..."
    when StatusCheckConfig::STALE
      "This check was marked as stale"
    else
      # no default
    end
  end

  def status_check_pending?(state)
    StatusCheckConfig.for(state)&.pending?
  end

  def time_to_complete(state, seconds)
    status_check_config = StatusCheckConfig.for(state)
    return "Skipped" if state == StatusCheckConfig::SKIPPED
    return "" if seconds.zero?
    return "" if seconds.negative?

    preposition = "after"
    if status_check_config&.success?
      preposition = "in"
    end

    adjective = StatusCheckConfig.adjective_state(state)
    if state == StatusCheckConfig::NEUTRAL
      adjective = "completed"
    end

    "#{adjective} #{preposition} #{duration(seconds)}"
  end

  def duration(seconds)
    case seconds
    when 0
      ""
    when (1..59)
      "#{seconds}s"
    else
      "#{seconds / 60}m"
    end
  end

  def billing_aware_duration(raw_seconds, hide_zero_seconds_remainder:)
    if raw_seconds <= 0
      return hide_zero_seconds_remainder ? "0m" : "0s"
    end

    # The actions billing hueristic rounds up to the nearest minute.
    # (In other words, any fraction of a minute consumed is billed as a full minute.)
    # To minimize customer confusion, we use .ceil (as opposed to .round) when displaying SECONDS.
    # This ensures, for example, that 60.000000001 seconds displays as "1m 1s" instead of "1m 0s".
    # This helps customers see that they clearly crossed over the threshold for that "billable minute."

    adjusted_seconds = raw_seconds.ceil
    total_minutes, remainder_seconds = adjusted_seconds.divmod(60)
    total_hours, remainder_minutes = total_minutes.divmod(60)
    total_days, remainder_hours = total_hours.divmod(24)

    fmt = ""
    fmt += "%1$dd " if total_days > 0
    fmt += "%2$dh " if total_days > 0 || remainder_hours > 0
    fmt += "%3$dm " if total_days > 0 || remainder_hours > 0 || remainder_minutes > 0
    fmt += "%4$ds" unless remainder_seconds == 0 && hide_zero_seconds_remainder
    fmt.strip!

    Kernel.format(fmt, total_days, remainder_hours, remainder_minutes, remainder_seconds)
  end

  def precise_duration(raw_seconds, simplified: false, hide_zero_seconds_remainder: false)
    seconds = raw_seconds.round
    minutes, remainder_seconds = seconds.divmod(60)
    hours, remainder_minutes = minutes.divmod(60)
    days, remainder_hours = hours.divmod(24)

    hide_zero_seconds = remainder_seconds.zero? && hide_zero_seconds_remainder

    if minutes < 1
      "#{seconds}s"
    elsif hours < 1
      if hide_zero_seconds
        "#{minutes}m"
      else
        "#{minutes}m #{remainder_seconds}s"
      end
    elsif days < 1
      if simplified || hide_zero_seconds
        "#{hours}h #{remainder_minutes}m"
      else
        "#{hours}h #{remainder_minutes}m #{remainder_seconds}s"
      end
    else
      if simplified
        "#{days}d #{remainder_hours}h"
      elsif hide_zero_seconds
        "#{days}d #{remainder_hours}h #{remainder_minutes}m"
      else
        "#{days}d #{remainder_hours}h #{remainder_minutes}m #{remainder_seconds}s"
      end
    end
  end

  def status_state_font_style(state)
    if StatusCheckConfig.for(state)&.pending?
      "text-italic"
    else
      "text-bold"
    end
  end

  def status_state_adjective(state)
    StatusCheckConfig.adjective_state(state)
  end

  # Public: Status summary for tooltip.
  #
  # status - A Status or CombinedStatus
  #
  # Returns String.
  def status_tooltip(status)
    case status
    when Status
      single_status_tooltip(status)
    when CombinedStatus
      if status.count > 1
        combined_status_tooltip(status)
      elsif status.count == 1
        single_status_tooltip(status.single_status)
      end
    end
  end

  # Public: Single Status summary.
  #
  # Used on status icon tooltip.
  #
  #   "Success: The Travis CI build passed"
  #
  # status - A single Status
  #
  # Returns String.
  def single_status_tooltip(status)
    [status.state.downcase.gsub("_", " ").capitalize, status.description].compact.join(": ")
  end

  # Public: Combined Status summary text of successful checks.
  #
  # Used on status icon tooltip.
  #
  # combined_status - A CombinedStatus
  #
  # Returns String.
  def combined_status_tooltip(combined_status)
    successful_count = combined_status.contexts.count { |context| StatusCheckConfig.for(context.state)&.success? }
    "#{successful_count} / #{combined_status.count} checks OK"
  end

  private

  # Calculate the combined state of status checks.
  #
  # status_checks - An enumerable collection of status check objects
  # workflows_pending_approval - An enumerable collection of workflows pending approval (default: [])
  #
  # Returns String representing the combined state:
  #   - "pending_approval" if there are workflows pending approval
  #   - "passed" if all checks succeeded
  #   - "failed" if all checks failed
  #   - "some_failed" if no pending checks and some failing checks
  #   - "pending_failed" if there are pending and failing checks
  #   - "pending" otherwise
  def calculate_combined_state(status_checks, workflows_pending_approval = [])
    if workflows_pending_approval.size > 0
      "pending_approval"
    elsif all_succeeded?(status_checks)
      "passed"
    elsif all_failing?(status_checks)
      "failed"
    elsif !any_pending?(status_checks) && any_failing?(status_checks)
      "some_failed"
    elsif any_pending?(status_checks) && any_failing?(status_checks)
      "pending_failed"
    else
      "pending"
    end
  end

  # Check if all status checks succeeded.
  #
  # status_checks - An enumerable collection of status check objects
  #
  # Returns Boolean.
  def all_succeeded?(status_checks)
    status_checks.any? &&
      status_checks.all? { |s| StatusCheckConfig::SUCCESS_STATES.include?(s.state) }
  end

  # Check if all status checks failed.
  #
  # status_checks - An enumerable collection of status check objects
  #
  # Returns Boolean.
  def all_failing?(status_checks)
    status_checks.any? &&
      status_checks.all? { |s| StatusCheckConfig::FAILURE_STATES.include?(s.state) }
  end

  # Check if any status checks are pending.
  #
  # status_checks - An enumerable collection of status check objects
  #
  # Returns Boolean.
  def any_pending?(status_checks)
    status_checks.any? { |s| StatusCheckConfig::PENDING_STATES.include?(s.state) }
  end

  # Check if any status checks are failing.
  #
  # status_checks - An enumerable collection of status check objects
  #
  # Returns Boolean.
  def any_failing?(status_checks)
    status_checks.any? { |s| StatusCheckConfig::FAILURE_STATES.include?(s.state) }
  end
end
