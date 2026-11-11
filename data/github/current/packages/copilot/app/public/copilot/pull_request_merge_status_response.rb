# typed: strict
# frozen_string_literal: true

module Copilot
  # Builds the "mergebox" / merge-readiness summary for a single pull request,
  # consumed by the GitHub Copilot desktop app (github/github-app) to replace
  # per-PR GraphQL polling with a single ETag-cacheable REST call.
  #
  # Reuses the React PR page's merge_box loaders/payloads
  # (PullRequests::PageData::MergeBox::*) so the merge-readiness signals stay
  # 1:1 with what the page renders, and supplements them with the additional
  # fields the desktop app currently derives from the public GraphQL API.
  class PullRequestMergeStatusResponse
    include StatusHelper
    include GitHub::Memoizer

    AVATAR_SIZE = T.let(40, Integer)
    STATUS_CHECKS_LIMIT = T.let(5, Integer)

    sig { params(pull_request: ::PullRequest, repository: ::Repository, viewer: ::User).void }
    def initialize(pull_request:, repository:, viewer:)
      @pull_request = pull_request
      @repository = repository
      @viewer = viewer
    end

    sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def payload
      {
        node_id: pull_request.global_relay_id,
        number: pull_request.number,
        title: pull_request.title,
        url: pull_request.permalink,
        state: pull_request.state.to_s.upcase,
        is_draft: pull_request.draft?,
        merged: pull_request.merged?,
        merged_at: pull_request.merged_at,
        base_ref_name: pull_request.base_ref_name,
        base_ref_oid: pull_request.base_sha,
        head_ref_name: head_ref_name,
        head_ref_oid: pull_request.head_sha,
        author: author_payload,
        created_at: pull_request.created_at,
        updated_at: pull_request.updated_at,
        labels: labels_payload,

        merge_state_status: merge_state_status,
        mergeable: mergeable,
        review_decision: review_decision,
        status_check_rollup: status_check_rollup_payload,

        merge_requirements: merge_requirements_payload,
        viewer_merge_actions: viewer_merge_actions_payload,
        pull_request_status: pull_request_status_payload,

        viewer_permission: viewer_permission,
        viewer_can_merge_as_admin: viewer_can_merge_as_admin,
        viewer_can_update_branch: pull_request_data.viewer_can_update_branch,
        viewer_can_enable_auto_merge: pull_request_data.viewer_can_enable_auto_merge,
        viewer_can_disable_auto_merge: pull_request_data.viewer_can_disable_auto_merge,
        repository: repository_payload,

        auto_merge_request: auto_merge_request_payload,
        is_merge_queue_enabled: pull_request.merge_queue_enabled?,
        is_in_merge_queue: pull_request.in_merge_queue?,
        merge_queue_entry: merge_queue_entry_payload,
      }
    end

    private

    sig { returns(::PullRequest) }
    attr_reader :pull_request

    sig { returns(::Repository) }
    attr_reader :repository

    sig { returns(::User) }
    attr_reader :viewer

    # Reuse the React PR page loader so the viewer permission booleans, merge
    # actions, auto-merge request, merge queue entry and merge state are
    # computed exactly as the page does (with the same DB-error fallbacks).
    sig { returns(T.untyped) } # rubocop:disable Sorbet/ForbidTUntyped
    memoize def pull_request_data
      ::PullRequests::PageData::MergeBox::PullRequestLoader.load(
        pull_request: pull_request,
        current_user: viewer,
      )
    end

    sig { returns(String) }
    def head_ref_name
      pull_request.head_ref.dup.force_encoding("utf-8")
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
    def author_payload
      author = pull_request.user
      return nil unless author

      {
        login: author.display_login,
        avatar_url: author.primary_avatar_url,
        type: author.bot? ? "Bot" : "User",
      }
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
    def labels_payload
      pull_request.labels.map do |label|
        {
          id: label.id,
          name: label.name,
          color: label.color,
        }
      end
    end

    sig { returns(String) }
    def merge_state_status
      pull_request_data.merge_state.to_s.upcase
    end

    # Mirrors the GraphQL `mergeable` enum so the desktop client sees the same
    # values it does today.
    sig { returns(String) }
    def mergeable
      case pull_request.git_merges_cleanly?
      when true then "MERGEABLE"
      when false then "CONFLICTING"
      else "UNKNOWN"
      end
    end

    sig { returns(T.nilable(String)) }
    def review_decision
      decision = pull_request.review_decision(viewer: viewer)
      decision&.to_s&.upcase
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
    def status_check_rollup_payload
      sha = pull_request.head_sha
      return nil if sha.blank?

      combined = ::CombinedStatus.new(repository, sha)
      return nil unless combined.any?

      { state: combined.state.to_s.upcase }
    rescue GitRPC::Error, ActiveRecord::ActiveRecordError
      nil
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
    def merge_requirements_payload
      data = ::PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(
        pull_request: pull_request,
        repository: repository,
        viewer: viewer,
        merge_action: nil,
        merge_method: nil,
        bypass_requirements: false,
      )
      return nil unless data

      {
        state: data.state.to_s.upcase,
        conditions: data.conditions.map { |condition| condition_payload(condition) },
        commit_message_headline: data.commit_message_headline,
        commit_message_body: data.commit_message_body,
        possible_commit_author_emails: data.possible_commit_author_emails,
      }
    end

    sig { params(condition: T.untyped).returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def condition_payload(condition)
      {
        __typename: condition_typename(condition.type),
        description: condition.description,
        display_name: condition.displayName,
        message: condition.message,
        result: condition.result.serialize,
      }
    end

    # Reproduces the GraphQL condition __typename (e.g. PullRequestStateCondition)
    # so the payload stays 1:1 with what the desktop app reads today.
    sig { params(type: T.untyped).returns(String) } # rubocop:disable Sorbet/ForbidTUntyped
    def condition_typename(type)
      "#{type.serialize.split("_").map(&:capitalize).join}Condition"
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
    def viewer_merge_actions_payload
      pull_request_data.allowable_merge_actions.map do |action|
        {
          name: action.name.to_s.upcase,
          merge_methods: action.merge_methods.map do |method|
            {
              name: method.name.to_s.upcase,
              is_default: method.is_default,
              allowable_status: method.allowable_status.to_s.upcase,
            }
          end,
        }
      end
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
    def pull_request_status_payload
      status = Platform::Models::PullRequestStatus.load_from_pull_request(
        pull_request,
        viewer: viewer,
      ).sync
      return nil unless status

      checks = status.status_checks
      # Match Objects::PullRequestStatus#status_checks: sort by state before
      # truncating so the desktop app sees the same first-N checks GraphQL returns.
      sorted = StableSorter.new(checks).sort_by { |check| StatusCheckConfig::STATE_SORT_ORDER[check.state] }
      {
        status_checks: sorted.first(STATUS_CHECKS_LIMIT).map { |check| status_check_payload(check) },
        status_rollup: status_rollup_payload(checks),
      }
    end

    sig { params(status: T.untyped).returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def status_check_payload(status)
      model = Platform::Models::StatusCheck.new(
        status: status,
        repository_id: pull_request.repository_id,
        pull_request: pull_request,
      )

      {
        id: model.id,
        avatar_url: status_check_avatar_url(status, size: AVATAR_SIZE),
        description: status.description || default_status_check_description(status.state),
        display_name: status.contextual_name || "",
        duration_in_seconds: status.duration_in_seconds,
        is_required: status_check_required?(status),
        state: status.state.to_s.upcase,
        target_url: status_check_target_url(status, pull_request),
        underlying_context: status_check_underlying_context(status),
      }
    end

    sig { params(status: T.untyped).returns(T::Boolean) } # rubocop:disable Sorbet/ForbidTUntyped
    def status_check_required?(status)
      case status
      when ::PullRequests::External::Domain::StatusChecks::IStatusCheck
        status.required?
      else
        status.required_for_pull_request?(pull_request) || false
      end
    end

    # status_checks always come from PullRequests::External::Domain::StatusChecks,
    # so each status is an External StatusCheckFinder::Record. Classify it as the
    # underlying commit Status vs CheckRun the desktop app reads today, without
    # reaching into packages/statuses' private ::Status.
    sig { params(status: T.untyped).returns(String) } # rubocop:disable Sorbet/ForbidTUntyped
    def status_check_underlying_context(status)
      case status
      when ::PullRequests::External::StatusCheckFinder::Record
        status.as_check_run ? "CheckRun" : "Status"
      when ::CombinedStatus::CheckRunAdapter
        "CheckRun"
      else
        "Status"
      end
    end

    sig { params(checks: T.untyped).returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def status_rollup_payload(checks)
      summary = checks
        .group_by { |check| StatusCheckConfig.enum_state(check.state) }
        .map { |state, statuses| { count: statuses.length, state: state.to_s.upcase } }

      {
        combined_state: status_rollup_combined_state(checks),
        summary: summary,
      }
    end

    # Matches Objects::StatusRollup#combined_state: the GraphQL combined-state
    # enum (PASSED/FAILED/SOME_FAILED/PENDING_FAILED/PENDING_APPROVAL/PENDING),
    # factoring in workflows awaiting approval, rather than the coarser
    # StatusCheckRollup.rollup_state (SUCCESS/FAILURE/PENDING).
    sig { params(checks: T.untyped).returns(String) } # rubocop:disable Sorbet/ForbidTUntyped
    def status_rollup_combined_state(checks)
      workflows_pending_approval = pull_request.action_required_check_suites(head_sha: pull_request.head_sha)
      calculate_combined_state(checks, workflows_pending_approval).upcase
    end

    sig { returns(T.nilable(String)) }
    def viewer_permission
      return nil unless viewer.user?

      permission = repository.role_based_access_level(viewer)
      permission&.to_s&.upcase
    end

    sig { returns(T::Boolean) }
    def viewer_can_merge_as_admin
      pull_request.async_can_bypass_merge_rules?(viewer).sync
    rescue ActiveRecord::ActiveRecordError
      false
    end

    sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def repository_payload
      {
        merge_commit_allowed: repository.merge_commit_allowed?,
        squash_merge_allowed: repository.squash_merge_allowed?,
        rebase_merge_allowed: repository.rebase_merge_allowed?,
        auto_merge_allowed: repository.auto_merge_allowed?,
      }
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
    def auto_merge_request_payload
      auto_merge_request = pull_request_data.auto_merge_request
      return nil unless auto_merge_request

      enabler = auto_merge_request.user
      {
        enabled_by: enabler && {
          login: enabler.display_login,
          avatar_url: enabler.primary_avatar_url,
        },
        merge_method: auto_merge_request.minimal_merge_method.to_s.upcase,
      }
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
    def merge_queue_entry_payload
      entry = pull_request_data.merge_queue_entry
      return nil unless entry

      {
        id: entry.global_relay_id,
        state: entry.state.to_s.upcase,
        position: entry.position,
        estimated_time_to_merge: estimated_time_to_merge(entry),
      }
    end

    sig { params(entry: T.untyped).returns(T.nilable(Integer)) } # rubocop:disable Sorbet/ForbidTUntyped
    def estimated_time_to_merge(entry)
      entry.async_time_to_merge_in_seconds.sync
    rescue ActiveRecord::ActiveRecordError
      nil
    end
  end
end
