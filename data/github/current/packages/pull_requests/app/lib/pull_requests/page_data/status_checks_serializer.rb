# typed: true
# frozen_string_literal: true

module PullRequests::PageData
  class StatusChecksSerializer
    include ViewModelHelper
    include StatusHelper
    include UrlHelper

    AVATAR_DEFAULT_SIZE = 40

    StatusCheckModel = T.type_alias do
      T.any(
        # pull_requests_status_checks_domain FF enabled:
        PullRequests::External::Domain::StatusChecks::IStatusCheck,

        # pull_requests_status_checks_domain FF disabled:
        RequiredStatusCheck,
        Status,
        CombinedStatus::CheckRunAdapter,
        InMemoryRequiredStatusCheck,
        RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType,
      )
    end

    sig { params(status_checks: T::Enumerable[StatusCheckModel], pull_request: PullRequest, avatar_size: T.nilable(Integer)).void }
    def initialize(status_checks:, pull_request:, avatar_size:)
      @status_checks = status_checks
      @pull_request = pull_request
      @avatar_size =  avatar_size || AVATAR_DEFAULT_SIZE
    end

    class StatusCheckState < T::Enum
      enums do
        ActionRequired = new("ACTION_REQUIRED")
        Cancelled = new("CANCELLED")
        Completed = new("COMPLETED")
        Error = new("ERROR")
        Expected = new("EXPECTED")
        Failure = new("FAILURE")
        InProgress = new("IN_PROGRESS")
        Neutral = new("NEUTRAL")
        Pending = new("PENDING")
        Queued = new("QUEUED")
        Requested = new("REQUESTED")
        Skipped = new("SKIPPED")
        Stale = new("STALE")
        StartupFailure = new("STARTUP_FAILURE")
        Success = new("SUCCESS")
        TimedOut = new("TIMED_OUT")
        Waiting = new("WAITING")
      end
    end

    class StatusCheckPayload < T::Struct
      const :description, T.nilable(String)
      const :durationInSeconds, Integer
      const :stateChangedAt, Time
      const :isRequired, T::Boolean
      const :displayName, String
      const :state, StatusCheckState
      const :targetUrl, T.nilable(String)
      const :avatarUrl, T.nilable(String)
      const :additionalContext, String
    end

    class StatusRollupCombinedState < T::Enum
      enums do
        Failed = new("FAILED")
        Passed = new("PASSED")
        Pending = new("PENDING")
        PendingApproval = new("PENDING_APPROVAL")
        PendingFailed = new("PENDING_FAILED")
        SomeFailed = new("SOME_FAILED")
      end
    end

    class CheckStateRollupPayload < T::Struct
      const :count, Integer
      const :state, StatusCheckState
    end

    class StatusRollupPayload < T::Struct
      const :summary, T::Array[CheckStateRollupPayload]
      const :combinedState, StatusRollupCombinedState
    end

    class StatusCheckAliveChannels < T::Struct
      const :commitHeadShaChannel, String
    end

    class StatusChecksPayload < T::Struct
      const :aliveChannels, StatusCheckAliveChannels
      const :statusChecks, T::Array[StatusCheckPayload]
      const :statusRollup, StatusRollupPayload
    end

    sig { params(include_immutable: T::Boolean).returns(T::Hash[T.untyped, T.untyped]) }
    def to_hash(include_immutable: true)
      statuses = @status_checks.sort_by { sort_order(_1) }.map do |status|
        StatusCheckPayload.new(
          description: status.description || default_status_check_description(status.state),
          durationInSeconds: status.duration_in_seconds,
          stateChangedAt: status.state_changed_at.to_time,
          isRequired: required?(status),
          displayName: status.contextual_name || "",
          state: StatusCheckState.deserialize(status.state.upcase),
          targetUrl: target_url(status),
          avatarUrl: avatar_url(status),
          additionalContext: additional_status_check_context(status.state, status.duration_in_seconds)
        )
      end

      payload = StatusChecksPayload.new(
        aliveChannels: alive_channels,
        statusChecks: statuses,
        statusRollup: StatusRollupPayload.new(
          summary: status_summary,
          combinedState: combined_state,
      ))

      payload.as_json

    end

    sig { returns(StatusRollupCombinedState) }
    private def combined_state
      if all_succeeded?
        StatusRollupCombinedState::Passed
      elsif !any_pending? && any_failing?
        StatusRollupCombinedState::SomeFailed
      elsif all_failing?
        StatusRollupCombinedState::Failed
      elsif any_pending? && any_failing?
        StatusRollupCombinedState::PendingFailed
      elsif workflows_pending_approval?
        StatusRollupCombinedState::PendingApproval
      else
        StatusRollupCombinedState::Pending
      end
    end

    sig { returns(T::Array[CheckStateRollupPayload]) }
    private def status_summary
      @status_checks
        .group_by { |status| StatusCheckConfig.enum_state(status.state) }
        .map { |state, statuses| CheckStateRollupPayload.new(count: statuses.length, state: StatusCheckState.deserialize(state.upcase)) }
    end

    sig { returns(StatusCheckAliveChannels) }
    private def alive_channels
      StatusCheckAliveChannels.new(
        commitHeadShaChannel: GitHub::WebSocket::Channels.signed_commit(@pull_request.base_repository, @pull_request.head_sha)
      )
    end

    sig { returns(T::Boolean) }
    private def all_succeeded?
      @status_checks.any? &&
        @status_checks.all? { |s| StatusCheckConfig::SUCCESS_STATES.include?(s.state) }
    end

    sig { returns(T::Boolean) }
    private def all_failing?
      @status_checks.any? &&
        @status_checks.all? { |s| StatusCheckConfig::FAILURE_STATES.include?(s.state) }
    end

    sig { returns(T::Boolean) }
    private def any_pending?
      @status_checks.any? { |s| StatusCheckConfig::PENDING_STATES.include?(s.state) }
    end

    sig { returns(T::Boolean) }
    private def any_failing?
      @status_checks.any? { |s| StatusCheckConfig::FAILURE_STATES.include?(s.state) }
    end

    sig { returns(T::Boolean) }
    private def workflows_pending_approval?
      # TODO: Don't make additional queries here. We already have all of the
      # checks in memory in the `@status_checks` ivar.
      @pull_request.action_required_check_suites(head_sha: @pull_request.head_sha).any?
    end

    sig { params(status: StatusCheckModel).returns([Integer, Integer, Integer, Integer, String]) }
    private def sort_order(status)
      # 'true' comes after 'false' in lexical sort order, but we want to show
      # things that evaluate to 'true' first. hopefully variables make this clearer
      first = 0
      second = 1
      [
        StatusCheckConfig::FAILURE_STATES.include?(status.state) ? first : second,
        StatusCheckConfig::PENDING_STATES.include?(status.state) ? first : second,
        StatusCheckConfig::INCOMPLETE_STATES.include?(status.state) ? first : second,
        StatusCheckConfig::SUCCESS_STATES.include?(status.state) ? first : second,
        status.context,
      ]
    end

    sig { params(status: StatusCheckModel).returns(T::Boolean) }
    private def required?(status)
      case status
      when PullRequests::External::Domain::StatusChecks::IStatusCheck
        status.required?
      else
        status.required_for_pull_request?(@pull_request) || false
      end
    end

    sig { params(status: StatusCheckModel).returns(T.nilable(String)) }
    private def avatar_url(status)
      if status.is_a?(PullRequests::External::Domain::StatusChecks::IStatusCheck)
        return status.avatar_url(@avatar_size)
      end

      if application = status.application
        application.preferred_avatar_url(size: @avatar_size)
      elsif creator = status.creator
        creator.primary_avatar_url(@avatar_size)
      elsif integration = status.integration # for InMemoryRequiredStatusCheck
        integration.bot&.primary_avatar_url(@avatar_size)
      else
        nil
      end
    end

    sig { params(status: StatusCheckModel).returns(T.nilable(String)) }
    private def target_url(status)
      case status
      when PullRequests::External::Domain::StatusChecks::IStatusCheck
        status.target_url(@pull_request)
      when CombinedStatus::CheckRunAdapter
        status.target_url(pull: @pull_request)
      when RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType
        status.target_url(pull_request_number: @pull_request.number)
      else
        status.target_url
      end
    end
  end
end
