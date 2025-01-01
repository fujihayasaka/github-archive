# typed: true
# frozen_string_literal: true

module PullRequests::PageData
  class StatusChecksSerializer
    include ViewModelHelper
    include StatusHelper
    include UrlHelper
    extend T::Sig

    AVATAR_DEFAULT_SIZE = 40

    StatusCheckModel = T.type_alias do
      T.any(
        RequiredStatusCheck,
        Status,
        CombinedStatus::CheckRunAdapter,
        InMemoryRequiredStatusCheck,
        RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType,
      )
    end

    sig { params(status_checks: T::Array[StatusCheckModel], pull_request: PullRequest, avatar_size: T.nilable(Integer)).void }
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
        if status.application
          avatar_url = status.application.preferred_avatar_url(size: @avatar_size)
        elsif status.creator
          avatar_url = status.creator.primary_avatar_url(@avatar_size)
        elsif status.integration # for InMemoryRequiredStatusCheck
          avatar_url = status.integration&.bot&.primary_avatar_url(@avatar_size)
        else
          avatar_url = nil
        end

        status_changed_at = T.cast(status.state_changed_at, Time)

        StatusCheckPayload.new(
          description: status.description || default_status_check_description(status.state),
          durationInSeconds: status.duration_in_seconds,
          stateChangedAt: status_changed_at,
          isRequired: T.unsafe(status).required_for_pull_request?(@pull_request) || false,
          displayName: T.unsafe(status).contextual_name || "",
          state: StatusCheckState.deserialize(status.state.upcase),
          targetUrl: status.target_url ? "#{status.target_url}?pr=#{@pull_request.number}" : nil,
          avatarUrl: avatar_url,
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
  end
end
