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

    sig { params(status_checks: T::Enumerable[StatusCheckModel], pull_request: PullRequest, pull_request_pending_workflow_approval_summary: T.nilable(PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary), avatar_size: T.nilable(Integer), include_copilot_check_run_failure_context: T::Boolean).void }
    def initialize(status_checks:, pull_request:, pull_request_pending_workflow_approval_summary:, avatar_size:, include_copilot_check_run_failure_context: false)
      @status_checks = status_checks
      @pull_request = pull_request
      @pull_request_pending_workflow_approval_summary = pull_request_pending_workflow_approval_summary
      @avatar_size = avatar_size || AVATAR_DEFAULT_SIZE
      @include_copilot_check_run_failure_context = include_copilot_check_run_failure_context
    end

    sig { params(status: StatusCheckModel).returns([Integer, Integer, Integer, Integer, String]) }
    def self.sort_order(status)
      StatusCheckConfig.sort_order_for(status)
    end

    # This struct maps 1:1 with the GraphQL enum Platform::Enums::StatusCheckState.
    # Any changes to this struct should be applied to the GQL enum as well.
    # @see app/platform/enums/status_check_state.rb
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

    class CopilotCheckRunFailureContext < T::Struct
      const :jobId, Integer
      const :headRef, T.nilable(String)
    end

    class StatusCheckPayload < T::Struct
      const :description, T.nilable(String)
      const :durationInSeconds, Integer
      const :stateChangedAt, Time
      const :isRequired, T::Boolean
      const :displayName, String
      const :state, StatusCheckState
      const :targetUrl, T.nilable(String)
      const :avatarBackgroundColor, T.nilable(String)
      const :avatarUrl, T.nilable(String)
      const :additionalContext, String
      const :copilotCheckRunFailureContext, T.nilable(CopilotCheckRunFailureContext)
    end

    # This struct maps 1:1 with the GraphQL enum Platform::Enums::StatusRollupCombinedState.
    # Any changes to this struct should be applied to the GQL enum as well.
    # @see app/platform/enums/status_rollup_combined_state.rb
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

    class PullRequestPendingWorkflowApprovalRollup < T::Struct
      const :workflowsRequiringApprovalCount, Integer
      const :viewerCanApproveWorkflowRuns, T::Boolean
      const :hasExpiredWorkflowRuns, T::Boolean
      const :approvalRequiredMessage, String
      const :helpLink, String
    end

    class StatusRollupPayload < T::Struct
      const :summary, T::Array[CheckStateRollupPayload]
      const :combinedState, StatusRollupCombinedState
      const :pendingWorkflowApprovalRollup, T.nilable(PullRequestPendingWorkflowApprovalRollup)
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
      statuses = @status_checks.sort_by { StatusChecksSerializer.sort_order(_1) }.map do |status|
        StatusCheckPayload.new(
          description: status.description || default_status_check_description(status.state),
          durationInSeconds: status.duration_in_seconds,
          stateChangedAt: status.state_changed_at.to_time,
          isRequired: required?(status),
          displayName: status.contextual_name || "",
          state: StatusCheckState.deserialize(status.state.upcase),
          targetUrl: target_url(status),
          avatarBackgroundColor: avatar_background_color(status),
          avatarUrl: avatar_url(status),
          additionalContext: status_additional_context(status),
          copilotCheckRunFailureContext: copilot_check_run_failure_context(status),
        )
      end

      payload = StatusChecksPayload.new(
        aliveChannels: alive_channels,
        statusChecks: statuses,
        statusRollup: StatusRollupPayload.new(
          summary: status_summary,
          combinedState: combined_state,
          pendingWorkflowApprovalRollup: @pull_request_pending_workflow_approval_summary&.rollup,
      ))

      payload.as_json
    end

    sig { params(status: StatusCheckModel).returns(String) }
    private def status_additional_context(status)
      status_check_additional_context(status.state, status.duration_in_seconds, status.state_changed_at)
    end

    sig { returns(StatusRollupCombinedState) }
    private def combined_state
      workflows_pending_approval = @pull_request_pending_workflow_approval_summary&.has_workflows_pending_approval? ? [1] : []
      state_string = calculate_combined_state(@status_checks, workflows_pending_approval)
      StatusRollupCombinedState.deserialize(state_string.upcase)
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
      status_check_avatar_url(status, size: @avatar_size)
    end

    sig { params(status: StatusCheckModel).returns(T.nilable(String)) }
    private def avatar_background_color(status)
      if application = status.application
        application.preferred_bgcolor
      elsif status.creator
        "#ffffff"
      end
    end

    sig { params(status: StatusCheckModel).returns(T.nilable(String)) }
    private def target_url(status)
      status_check_target_url(status, @pull_request)
    end

    sig { params(status: StatusCheckModel).returns(T.nilable(CopilotCheckRunFailureContext)) }
    private def copilot_check_run_failure_context(status)
      return nil unless @include_copilot_check_run_failure_context

      job_id = status_check_copilot_failure_job_id(status)
      return nil unless job_id

      # Get head_ref from the pull request
      head_ref = @pull_request.head_ref

      CopilotCheckRunFailureContext.new(jobId: job_id, headRef: head_ref)
    end
  end
end
