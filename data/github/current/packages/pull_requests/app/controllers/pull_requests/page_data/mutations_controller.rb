# rubocop:disable GitHub/UseRestfulActions
# typed: true
# frozen_string_literal: true

class PullRequests::PageData::MutationsController < AbstractRepositoryController
  include GitHub::RateLimitedRequest
  include JsonDependency
  include VerifiedFetchDependency
  include ::MergeQueues::SharedControllerMethods
  include PullRequests::DatabaseSelection
  include CommentsHelper

  allow_verified_fetch

  before_action :login_required
  before_action :require_xhr
  before_action :load_pull_request
  before_action :parse_json_params
  before_action :auto_merge_content_authorization_required, only: [:enable_auto_merge, :disable_auto_merge]
  before_action :update_content_authorization_required, only: [
    :close_pull_request,
    :reopen_pull_request,
    :convert_to_draft,
    :delete_head_ref,
    :restore_head_ref,
    :merge,
    :mark_ready_for_review,
    :stack_rebase,
    :enqueue_stack,
    :unstack_pull_requests,
    :update_description,
    :update_pull_request_branch,
  ]
  skip_before_action :set_repo_as_hovercard_subject
  before_action :merge_queue_required, only: [:dequeue_pull_request]
  before_action :writable_repository_required, only: [:merge, :cleanup_codespaces]
  before_action :require_prx_files, only: [
    :create_review_comment,
    :update_review_comment,
    :delete_review_comment,
    :submit_review,
    :abandon_review,
    :resolve_thread,
    :unresolve_thread,
    :hide_comment,
    :unhide_comment,
    :submit_copilot_groups_feedback
  ]
  before_action :load_review_thread, only: [:resolve_thread, :unresolve_thread]
  before_action :load_comment, only: [:hide_comment, :unhide_comment]
  before_action :pull_request_comment_create_content_authorization_required, only: [:create_timeline_comment, :create_review_comment]
  before_action :pull_request_comment_update_content_authorization_required, only: [:update_review_comment]

  prepend_around_action :use_repository_cluster_replicas, only: [:submit_review]
  prepend_around_action :use_user_cluster_replicas, only: [:merge]

  WRITE_RATE_LIMIT = 60
  RATE_LIMIT_REACHED = "Your browser sent requests too quickly"

  OUT_OF_DATE_DIFF_ERROR = "This diff is outdated, please refresh and try again."
  MISSING_PARENT_ERROR = "The comment you are replying to has been deleted."

  EMOTION_PLATFORM_ENUMS_TO_CONTENT = {
    "THUMBS_UP"   => "+1",
    "THUMBS_DOWN" => "-1",
    "LAUGH"       => "smile",
    "HOORAY"      => "tada",
    "CONFUSED"    => "thinking_face",
    "HEART"       => "heart",
    "ROCKET"      => "rocket",
    "EYES"        => "eyes",
  }

  rate_limit_requests \
    if: :logged_in?,
    max: WRITE_RATE_LIMIT, # per minute
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, # 1.minute
    key: :default_rate_limit_key,
    at_limit: :render_rate_limited_response

  rescue_from_timeout_without_replay only: [:merge] do
    T.bind(self, PullRequests::PageData::MutationsController)
    if FeatureFlag.vexi.enabled?(:merge_timeout_check_completion, default: false)
      merged = @pull_request&.reload&.merged?
      outcome = merged ? "completed" : "timeout"
      GitHub.dogstats.increment("pull_requests.merge_timeout_rescued", tags: ["outcome:#{outcome}"])
    else
      GitHub.dogstats.increment("pull_requests.merge_timeout_rescued")
    end

    orchestration = PullRequests::Orchestrations::Merge.active.find_by(pull_request_id: @pull_request&.id)
    orchestration&.end_orchestration(:failed, "merge timed out")

    # This should not affect repos that use the merge queue, since that will _always_ generate a merge commit
    # as part of the process of the queue.
    @pull_request&.update_mergeable_attribute(nil)
    @pull_request&.enqueue_mergeable_update(priority: :high)

    render json: { error: "Merge attempt timed out." }, status: :gateway_timeout
  end

  # Removes all pull requests from given stack
  def unstack_pull_requests
    return render_404 unless PullRequests::Stacks.enabled?(current_repository)

    # User must be author or have push access to repo. See Issue#can_modify?
    unless T.must(@pull_request.issue).can_modify?(current_user)
      return render status: :unauthorized, json: { success: false, error: "User is not authorized to unstack pull requests." }
    end

    stack = @pull_request.stack
    return render_404 unless stack

    # Confirm that the stack to be deleted is associated with the given pull request
    return render_404 unless stack.id == params[:stack_id].to_i

    result = PullRequests::Stacks.unstack(stack, actor: current_user)
    case result
    when PullRequests::Stacks::Unstack::Service::Success
      @pull_request.notify_git_merge_state_channel
      render(
        status: :ok,
        json: { success: true, message: "Pull requests successfully unstacked." },
      )
    when PullRequests::Stacks::Error
      pull_request_errors = result.pulls&.map do |pull|
        {
          number: pull.number,
          unstackabilityReason: pull.locked_stack_entry_reason&.serialize,
        }
      end

      render(
        status: result.http_status,
        json: {
          success: false,
          error: result.message,
          failureReason: result.reason.serialize,
          pullRequestErrors: pull_request_errors,
        },
      )
    else
      T.absurd(result)
    end
  rescue => e
    Failbot.report(e)
    render(
      status: 500,
      json: {
        success: false,
        error: "An unexpected error occurred while attempting to unstack pull requests.",
      }
    )
  end

  def enable_auto_merge
    # Only the pull request author is allowed to override the email for the squash commit.
    # This validation works for squash only if the pull request author is selecting an email.
    author_email = params[:authorEmail].presence || current_user.git_author_email
    if current_user.is_enterprise_managed?
      return render_404 unless current_user.profile_email == author_email
      email = current_user.emails.find_by(email: current_user.email)
    else
      return render_404 unless email = current_user.emails.find_by(email: author_email)
    end

    # For merge_queue, params[:mergeMethod] is either GROUP or SOLO
    # For all other cases, params[:mergeMethod] is either MERGE, SQUASH, or REBASE
    # This is due to the way auto-merge is modeled.
    # When merge_queue is present, get the actual merge method from the queue config
    # to ensure proper caching and validation downstream.

    merge_queue = MergeQueue.for(repository: @pull_request.base_repository, branch: @pull_request.base_ref)

    merge_method = if merge_queue
      config = MergeQueues.configuration_for(merge_queue)
      config.merge_method.serialize.to_sym
    else
      determine_merge_method(params[:mergeMethod])
    end

    merge_state = @pull_request.cached_merge_state(viewer: current_user, merge_method: merge_method)

    am_logger.append_pull_request_context(@pull_request)
    am_logger.append_repository_context(@pull_request.repository)

    log_context = {
      user_id: current_user.id,
      user_login: current_user.display_login,
      params_merge_method: params[:mergeMethod],
      merge_method: merge_method,
      merge_queue_present: merge_queue.present?,
      merge_state_status: merge_state.status,
      merge_state_clean: merge_state.clean?,
      pr_state: @pull_request.state,
      pr_draft: @pull_request.draft?,
      pr_merged: @pull_request.merged?,
    }

    am_logger.append(log_context)
    am_logger.flush
    am_logger.detach(log_context.keys)

    begin
      ### AUTO MERGE - REFACTORED PATH ###
      if FeatureFlag.vexi.enabled?(:am_refactor_enable_auto_merge_entrypoint, @pull_request.repository, default: false)
        log_debug("gh.pull_request.enable_auto_merge.refactored_path", pull_request_id: @pull_request.id)

        log_debug(
          "gh.pull_request.enable_auto_merge.refactored_path.evaluation",
          pull_request_id: @pull_request.id,
          merge_queue_present: merge_queue.present?,
          merge_state_clean: merge_state.clean?,
          will_enqueue_to_merge_queue: merge_queue.present?,
          will_direct_merge: !merge_queue.present? && merge_state.clean?,
          will_async_merge: !merge_queue.present? && !merge_state.clean?
        )

        if merge_queue # enqueue_auto_merge
          log_debug("gh.pull_request.enable_auto_merge.refactored_path.merge_queue", pull_request_id: @pull_request.id, merge_queue_id: merge_queue.id)

          validation_result = validate_commit_parameters(merge_method)
          if validation_result.present?
            message = validation_result[:message]
            status = validation_result[:status]
            metadata = validation_result[:metadata]

            return render_status(status, message, metadata:)
          end

          AutoMergeRequest.enqueue!(
            pull_request: @pull_request,
            merge_method: params[:mergeMethod]&.downcase,
            user: current_user,
            email: email,
            commit_title: params[:commitTitle],
            commit_message: params[:commitMessage],
            remote_ip: request.remote_ip,
          )

          render json: { message: "Auto merge request successfully created" }, status: :ok

        elsif merge_state.clean? # merge_clean_status
          log_debug("gh.pull_request.enable_auto_merge.refactored_path.clean_status", pull_request_id: @pull_request.id)
          GitHub.dogstats.increment("pull_request.merge_attempt", tags: ["action:enable_auto_merge"])

          # Omit `commit_author_email` until we enable selecting the commit author (see: https://github.com/github/pull-requests/issues/8489)
          handle_merge_response = handle_merge(:enable_auto_merge_refactored, merge_method, include_email: false)
          message = handle_merge_response[:message]
          status = handle_merge_response[:status]
          metadata = handle_merge_response[:metadata]

          set_sticky_merge_method(merge_method)
          render_status(status, message, metadata:)

        else # merge_async
          log_debug("gh.pull_request.enable_auto_merge.refactored_path.async_merge", pull_request_id: @pull_request.id)
          commit_validation_result = validate_commit_parameters(merge_method)
          if commit_validation_result.present?
            message = commit_validation_result[:message]
            status = commit_validation_result[:status]
            metadata = commit_validation_result[:metadata]

            return render_status(status, message, metadata:)
          end

          case auto_merge_result = PullRequests::AsyncMerge.call(
            pull_request: @pull_request,
            repository: @pull_request.repository,
            actor: current_user,
            mode: :wait,
            merge_method:,
            commit_title: params[:commitTitle],
            commit_message: params[:commitMessage],
            commit_email_address: email,
            actor_ip_address: request.remote_ip
          )
          when PullRequests::Merge::Results::Created
            log_debug("gh.pull_request.enable_auto_merge.refactored_path.async_merge.created", pull_request_id: @pull_request.id, message: "Auto merge request successfully created")
            render json: { message: "Auto merge request successfully created" }, status: :ok
          when PullRequests::Merge::Results::AlreadyEnqueued
            log_debug("gh.pull_request.enable_auto_merge.refactored_path.async_merge.already_enqueued", pull_request_id: @pull_request.id, message: "Auto merge is already enabled")
            render json: { error: "Auto merge is already enabled" }, status: :unprocessable_entity
          when PullRequests::Merge::Results::AlreadyMerged
            log_debug("gh.pull_request.enable_auto_merge.refactored_path.async_merge.already_merged", pull_request_id: @pull_request.id, message: "Pull request is already merged")
            render json: { error: "Pull request is already merged" }, status: :unprocessable_entity
          when PullRequests::Merge::Results::Invalid
            log_debug(
              "gh.pull_request.enable_auto_merge.refactored_path.async_merge.invalid",
              pull_request_id: @pull_request.id,
              message: auto_merge_result.message,
              failed_rule_types: auto_merge_result.failed_rules.map(&:serialize)
            )
            render json: { error: auto_merge_result.message }, status: :unprocessable_entity
          when PullRequests::Merge::Results::Error
            log_debug("gh.pull_request.enable_auto_merge.refactored_path.async_merge.error", pull_request_id: @pull_request.id, message: auto_merge_result.message)
            render json: { error: auto_merge_result.message }, status: :unprocessable_entity
          else
            T.absurd(auto_merge_result)
          end
        end
      else
        ### AUTO MERGE - LEGACY PATH ###
        am_logger.append({ codepath: "legacy_path" })

        can_enable_auto_merge_result = @pull_request.can_enable_auto_merge(actor: current_user)
        clean_status = can_enable_auto_merge_result.reason&.include?("clean status")

        evaluation_log_context = {
          allowed: can_enable_auto_merge_result.allowed?,
          reason: can_enable_auto_merge_result.reason,
          rejection_category: can_enable_auto_merge_result.rejection_category&.to_s,
          clean_status_derived: clean_status,
          merge_queue_present: merge_queue.present?,
          will_enqueue: can_enable_auto_merge_result.allowed? || merge_queue.present?,
          will_direct_merge: !can_enable_auto_merge_result.allowed? && !merge_queue.present? && clean_status,
          will_error: !can_enable_auto_merge_result.allowed? && !merge_queue.present? && !clean_status,
        }

        am_logger.append(evaluation_log_context, prefix: "gh.pull_request.enable_auto_merge.evaluation")
        am_logger.flush
        am_logger.detach(evaluation_log_context.keys)

        if can_enable_auto_merge_result.allowed? || merge_queue
          merge_queue_context = {
            allowed: can_enable_auto_merge_result.allowed?,
            merge_queue_present: merge_queue.present?,
          }

          am_logger.append(merge_queue_context, prefix: "gh.pull_request.enable_auto_merge.merge_queue_enqueue")
          am_logger.flush
          am_logger.detach(merge_queue_context.keys)

          validation_result = validate_commit_parameters(merge_method)
          if validation_result.present?
            message = validation_result[:message]
            status = validation_result[:status]
            metadata = validation_result[:metadata]

            validation_result_context = {
              status: status,
              message: message,
              metadata: metadata[:ruleErrors] || {},
            }
            am_logger.append(validation_result_context, prefix: "gh.pull_request.enable_auto_merge.merge_queue_enqueue.validation_result")
            am_logger.append_outcome("merge queue enqueue failure", prefix: "gh.pull_request.enable_auto_merge.merge_queue_enqueue")
            am_logger.flush
            return render_status(status, message, metadata:)
          end

          AutoMergeRequest.enqueue!(
            pull_request: @pull_request,
            merge_method: params[:mergeMethod]&.downcase,
            user: current_user,
            email: email,
            commit_title: params[:commitTitle],
            commit_message: params[:commitMessage],
            remote_ip: request.remote_ip,
          )
          am_logger.append_outcome("merge queue enqueue success", prefix: "gh.pull_request.enable_auto_merge.merge_queue_enqueue")
          am_logger.flush
          render json: { message: "Auto merge request successfully created" }, status: :ok
        elsif clean_status
          am_logger.append({
            clean_status: true,
            can_enable_auto_merge_result_reason: can_enable_auto_merge_result.reason,
          })
          am_logger.flush
          GitHub.dogstats.increment("pull_request.merge_attempt", tags: ["action:enable_auto_merge"])

          # Omit `commit_author_email` until we enable selecting the commit author (see: https://github.com/github/pull-requests/issues/8489)
          handle_merge_response = handle_merge(:enable_auto_merge_legacy, merge_method, include_email: false)
          message = handle_merge_response[:message]
          status = handle_merge_response[:status]
          metadata = handle_merge_response[:metadata]

          set_sticky_merge_method(merge_method)
          am_logger.detach([:clean_status, :can_enable_auto_merge_result_reason])
          am_logger.append({
            status: status,
          })
          am_logger.append_outcome("legacy path clean status complete")
          am_logger.flush
          render_status(status, message, metadata:)
        else
          am_logger.append({
            can_enable_auto_merge_result_reason: can_enable_auto_merge_result.reason,
          })
          am_logger.append_outcome("legacy path error")
          am_logger.flush
          render json: { error: can_enable_auto_merge_result.reason }, status: :unprocessable_entity
        end
      end
    rescue AutoMergeRequest::Invalid => e
      log_am_error(
        "gh.pull_request.enable_auto_merge.exception",
        pull_request_id: @pull_request.id,
        message: e.message
      )
      render json: { error: "Failed enabling auto-merge for pull request" }, status: :unprocessable_entity
    end
  end

  def cleanup_codespaces
    return render_404 unless @pull_request.head_repository.pushable_by?(current_user)
    codespaces = @pull_request.codespaces.can_be_deprovisioned_by_user(current_user)

    result = codespaces.all? do |codespace|
      codespace.deprovision!(reason: Codespace.deletion_reasons[:user_requested])
    end

    GitHub.dogstats.increment("codespaces.merge_merge_cleanup", tags: ["#{result ? "result:success" : "error:invalid"}"])

    if result
      render json: { message: "#{'Codespace'.pluralize(codespaces.size)} deleted successfully." }, status: :ok
    else
      render json: { error: "Some codespaces could not be deleted." }, status: :unprocessable_entity
    end
  end

  def disable_auto_merge
    return render_404 unless @pull_request.can_disable_auto_merge?(actor: current_user)

    if @pull_request.auto_merge_request
      @pull_request.auto_merge_request.disable(:manually_disabled, actor: current_user)
      @pull_request.reload

      if !@pull_request.auto_merge_request
        render json: { message: "Auto merge request successfully disabled" }, status: :ok
      else
        render json: { error: "Failed disabling auto-merge for pull request" }, status: :unprocessable_entity
      end
    end
  rescue AutoMergeRequest::Invalid => e
    render json: { error: "Failed disabling auto-merge for pull request" }, status: :unprocessable_entity
  end

  def restore_head_ref
    if @pull_request.restore_head_ref(current_user)
      render json: { message: "Head ref was successfully restored" }, status: :ok
    else
      render json: { error: "Failed to restore head ref" }, status: :unprocessable_entity
    end
  end

  def delete_head_ref
    if @pull_request.cleanup_head_ref(current_user)
      render json: { message: "Head ref was successfully deleted" }, status: :ok
    else
      render json: { error: "Could not delete head ref" }, status: :unprocessable_entity
    end
  end

  def mark_ready_for_review
    return render_404 unless @pull_request.can_change_draft_state?(current_user)

    @pull_request.ready_for_review!(user: current_user)

    render json: { message: "Pull request was successfully marked ready for review" }, status: :ok
  rescue => exception
    Failbot.report!(exception)
    render json: { error: "Pull request failed to be marked as ready for review" }, status: :internal_server_error
  end

  def convert_to_draft
    return render_404 unless @pull_request.can_convert_to_draft?(current_user)

    @pull_request.convert_to_draft(user: current_user)

    render json: { message: "Pull request was successfully converted to a draft" }, status: :ok
  rescue => exception
    Failbot.report!(exception)
    render json: { error: "Pull request failed to be converted to a draft" }, status: :internal_server_error
  end

  def close_pull_request
    return render_404 unless @pull_request.closable_by?(current_user)
    return render_404 unless @pull_request.open?

    unless @pull_request.close(current_user)
      return render json: { error: "Pull request failed to close" }, status: :unprocessable_entity
    end

    render json: { message: "Pull request was successfully closed" }, status: :ok
  rescue => exception
    Failbot.report!(exception)
    render json: { error: "Pull request failed to close" }, status: :internal_server_error
  end

  def reopen_pull_request
    return render_404 unless @pull_request.closed?
    return render_404 unless @pull_request.reopenable_by?(current_user)

    if PullRequestCreationConfig.new(current_repository).pull_request_exceeds_limit?(@pull_request)
      return render json: { error: "You've reached the open pull request limit for this repository" }, status: :unprocessable_entity
    end

    unless @pull_request.open(current_user)
      return render json: { error: "Pull request failed to reopen" }, status: :unprocessable_entity
    end

    render json: { message: "Pull request was successfully reopened" }, status: :ok
  rescue => exception
    Failbot.report!(exception)
    render json: { error: "Pull request failed to reopen" }, status: :internal_server_error
  end

  def merge
    if invalid_author_email?(params[:authorEmail])
      GitHub.dogstats.increment("pull_request", tags: ["action:merge", "error:invalid"])
      return render json: { error: "Invalid email for web commit." }, status: :unprocessable_entity
    end

    allowable_merge_methods = @pull_request.async_allowable_merge_methods(actor: current_user).sync

    merge_method = determine_merge_method(params[:mergeMethod])

    merge_method_setting = case merge_method
    when :merge
      allowable_merge_methods.merge_commit
    when :squash
      allowable_merge_methods.squash_merge
    when :rebase
      allowable_merge_methods.rebase_merge
    else
      PullRequest::MergeMethodSettings::Value::Disallowed
    end

    metadata = nil

    if merge_method_setting.error?
      message = "Failed to load repository settings. Please wait a few minutes and then try again."
      status = :unprocessable_entity
    elsif merge_method_setting.disallowed?
      message = "The selected merge method (#{merge_method}) is not allowed."
      status = :unprocessable_entity
    elsif @pull_request.git_merges_cleanly? && @pull_request.base_repository.pushable_by?(current_user)
      GitHub.dogstats.increment("pull_request", tags: ["action:merge"])

      source = params[:bypassBranchProtections] == "true" ? :admin_override_merge : :direct_merge

      handle_merge_response = handle_merge(:merge_pr_page_data_mutations, merge_method, source)
      message = handle_merge_response[:message]
      status = handle_merge_response[:status]
      metadata = handle_merge_response[:metadata]

      set_sticky_merge_method(merge_method)
    else
      message = "We couldn’t merge this pull request."
      status = :unprocessable_entity
    end
    render_status(status, message, metadata:)
  end

  def dequeue_pull_request
    dequeued_entry = merge_queue.entry_for(pull_request: @pull_request)

    if dequeued_entry.nil?
      return render json: { message: "Pull request was successfully removed from the merge queue." }, status: :ok
    end

    return render_404 unless dequeued_entry.adminable_by?(current_user)

    dequeued = merge_queue.dequeue(
      pull_request: @pull_request,
      dequeuer: current_user,
      raise_group_locked_error: true)

    if !dequeued
      render json: { error: "Failed to remove pull request from the merge queue." }, status: :unprocessable_entity and return
    end

    render json: { message: "Pull request was successfully removed from the merge queue." }, status: :ok
  rescue MergeQueues::Errors::GroupLocked
    render json: { error: "Failed to remove pull request from the merge queue because the group is locked." }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "Failed to remove pull request from the merge queue: #{e.record.errors.full_messages.to_sentence}." }, status: :unprocessable_entity
  end

  def enqueue_stack
    return render_404 unless PullRequests::Stacks.enabled?(current_repository)

    # User must be author or have push access to repo. See Issue#can_modify?
    unless T.must(@pull_request.issue).can_modify?(current_user)
      return render status: :unauthorized, json: { error: "User is not authorized to enqueue this stack." }
    end

    stack = T.let(@pull_request.stack, T.nilable(PullRequests::Stack))
    return render_404 unless stack

    # Resolve the author email for the merge commit
    author_email = params[:authorEmail].presence || current_user.git_author_email
    if current_user.is_enterprise_managed?
      return render_404 unless current_user.profile_email == author_email
      email = current_user.emails.find_by(email: current_user.email)
    else
      return render_404 unless email = current_user.emails.find_by(email: author_email)
    end

    merge_method = determine_merge_method(params[:mergeMethod])

    validation_result = validate_commit_parameters(merge_method)
    if validation_result.present?
      return render_status(validation_result[:status], validation_result[:message], metadata: validation_result[:metadata])
    end

    result = PullRequests::Stacks::Enqueue.call(
      pull_request: @pull_request,
      actor: current_user,
      email:,
      commit_title: params[:commitTitle],
      commit_message: params[:commitMessage],
      remote_ip: request.remote_ip,
      merge_method:
    )

    case result
    when PullRequests::Stacks::Merging::Result::Success
      render json: { message: "Stack enqueue request successfully created" }, status: :ok
    when PullRequests::Stacks::Merging::Result::NoLongerStacked
      render json: { error: "Pull request is no longer part of a stack" }, status: :unprocessable_entity
    when PullRequests::Stacks::Merging::Result::Error
      render json: { error: result.message }, status: :unprocessable_entity
    else
      T.absurd(result)
    end
  end

  def stack_rebase
    return render_404 unless PullRequests::Stacks.enabled?(current_repository)

    # User must be author or have push access to repo. See Issue#can_modify?
    unless T.must(@pull_request.issue).can_modify?(current_user)
      return render status: :unauthorized, json: { error: "User is not authorized to rebase this stack." }
    end

    stack = @pull_request.stack
    return render_404 if stack.nil?

    return render json: { error: "Missing expectedHeadOids parameter" }, status: :unprocessable_entity if params[:expectedHeadOids].nil?

    expected_head_oid_by_pr_number = params[:expectedHeadOids].to_unsafe_h.transform_keys(&:to_i)
    result = PullRequests::Stacks.update_all_branches_later(
      stack:,
      actor: T.must(current_user),
      expected_head_oid_by_pr_number:,
    )

    case result
    when PullRequests::Stacks::UpdateAllBranches::EnqueueService::Success
      render(json: {})
    when PullRequests::Stacks::UpdateAllBranches::EnqueueService::AlreadyRunning
      render json: { error: "Rebase is already in progress" }, status: :conflict
    when PullRequests::Stacks::Error
      render json: { error: result.message }, status: result.http_status
    else
      T.absurd(result)
    end
  end

  def update_pull_request_branch
    update_method = params[:updateMethod]&.downcase == "rebase" ? "rebase" : "merge"
    feature = update_method == "rebase" ? :update_branch_web_react_rebase : :update_branch_web_react_merge
    result = PullRequests::UpdateBranch.execute(
      pull_request: @pull_request,
      user: T.must(current_user),
      update_method:,
      expected_head_oid: params[:expectedHeadOid],
      feature: feature
    )

    case result
    when PullRequests::UpdateBranch::Success
      render json: { orchestration: { url: pull_request_orchestration_status_url(orchestration_id: result.orchestration.id) } }
    when PullRequests::UpdateBranch::Error
      render json: { error: result.error_message }, status: :unprocessable_entity
    else
      T.absurd(result)
    end
  end

  def dismiss_review
    review = @pull_request.reviews.find(params[:reviewId])
    return render_404 unless review.present?
    result = PullRequests::DismissReview.execute(review: review, user: T.must(current_user), message: params[:message])

    case result
    when PullRequests::DismissReview::Success
      render json: { message: "Review was successfully dismissed." }, status: :ok
    when PullRequests::DismissReview::Error
      status = result.failure_reason == PullRequests::DismissReview::Error::NotPermitted ? :not_found : :unprocessable_entity
      render json: { error: result.error_message }, status: status
    else
      T.absurd(result)
    end
  end

  def re_request_review_from_user
    if params[:reviewerLogin].blank?
      return render json: { error: "Reviewer login is required." }, status: :unprocessable_entity
    end
    reviewer = User.find_by(login: params[:reviewerLogin])
    return render_404 unless reviewer.present?
    if @pull_request.request_review_from(reviewers: [reviewer], actor: current_user, re_request: true, append: true)
      render json: { message: "Review request was successfully re-requested." }, status: :ok
    else
      Failbot.push_sensitive("gh.pull_request.re_request_reviews_validation_errors" => @pull_request.errors.full_messages.to_sentence)
      render json: { error: "Failed to re-request review." }, status: :unprocessable_entity
    end
  end

  def re_request_review_from_team
    if params[:teamName].blank?
      return render json: { error: "Team name is required." }, status: :unprocessable_entity
    end
    # note: the team name should not include the @ at the beginning!
    reviewer = if @pull_request.repository.organization&.business_team_pr_reviewers_enabled?
      Orgs.domain.teams.find_team_with_organization_context(@pull_request.repository.organization, team_slug: params[:teamName].delete_prefix("/"))
    else
      Team.find_by_combined_slug(params[:teamName])
    end

    return render_404 unless reviewer.present?
    if @pull_request.request_review_from(reviewers: [reviewer], actor: current_user, re_request: true, append: true)
      render json: { message: "Review request was successfully re-requested." }, status: :ok
    else
      Failbot.push_sensitive("gh.pull_request.re_request_reviews_validation_errors" => @pull_request.errors.full_messages.to_sentence)
      render json: { error: "Failed to re-request review." }, status: :unprocessable_entity
    end
  end

  def add_suggested_reviewer
    if params[:reviewerLogin].blank?
      return render json: { error: "Reviewer login is required." }, status: :unprocessable_entity
    end
    reviewer = User.find_by(login: params[:reviewerLogin])
    return render_404 unless reviewer.present?
    if @pull_request.request_review_from(reviewers: [reviewer], actor: current_user, append: true)
      render json: { message: "Suggested reviewer was successfully added." }, status: :ok
    else
      Failbot.push_sensitive("gh.pull_request.add_suggested_reviewer_validation_errors" => @pull_request.errors.full_messages.to_sentence)
      render json: { error: "Failed to add suggested reviewer." }, status: :unprocessable_entity
    end
  end

  # Modify the set of pending reviewers on a pull request in a single call.
  def modify_reviewers
    result = PullRequests::PageData::Overview::ReviewRequests::ModifyReviewers.call(
      pull_request: @pull_request,
      actor: T.must(current_user),
      add_reviewers: params[:addReviewers],
      remove_reviewers: params[:removeReviewers],
    )

    case result
    when PullRequests::PageData::Overview::ReviewRequests::ModifyReviewers::Success
      render json: { message: "Reviewers were successfully updated." }, status: :ok
    when PullRequests::PageData::Overview::ReviewRequests::ModifyReviewers::InvalidPayload
      render json: { error: result.message }, status: :unprocessable_entity
    when PullRequests::PageData::Overview::ReviewRequests::ModifyReviewers::NotFound
      render json: { error: result.message }, status: :not_found
    when PullRequests::PageData::Overview::ReviewRequests::ModifyReviewers::Failure
      Failbot.push_sensitive("gh.pull_request.modify_reviewers_validation_errors" => result.message)
      render json: { error: "Failed to modify reviewers." }, status: :unprocessable_entity
    else
      T.absurd(result)
    end
  end

  # Creates a regular, non-review (i.e. timeline) comment on the PR timeline.
  # For the time being, this is only needed for Copilot Mission Control to be able
  # to post comments mentioning Copilot in order to kick off new agent sessions but
  # will eventually be supported more generally.
  #
  # There is some functionality missing here from the implementation of the #comment
  # method in the app/controllers/pull_requests_controller.rb file.
  def create_timeline_comment
    # Validate required parameters
    text = params[:text]
    if text.blank?
      return render json: { error: "Comment text is required." }, status: :unprocessable_entity
    end

    issue = @pull_request.issue

    begin
      comment = issue.create_comment(current_user, text)

      if comment.persisted?
        GitHub.instrument "comment.create", user: current_user
        GitHub.dogstats.increment("pull_request.timeline_comment.created")

        issue_comment_payload = build_issue_comment_payload(comment)&.as_json
        render json: {
          message: "Comment created successfully.",
          commentId: comment.id,
          issueComment: issue_comment_payload
        }, status: :ok
      else
        render json: { error: comment.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: "Failed to create comment: #{e.record.errors.full_messages.to_sentence}" }, status: :unprocessable_entity
    rescue => exception
      Failbot.report!(exception)
      GitHub.dogstats.increment("pull_request.timeline_comment.error", tags: ["error:#{exception.class.name&.demodulize}"])
      render json: { error: "Failed to create comment." }, status: :internal_server_error
    end
  end

  # Create a PullRequestReviewComment, and required PullRequestReview and/or
  # PullRequestReviewThread if necessary
  def create_review_comment
    result = data = comment_database_id = nil
    replying = params[:inReplyTo].present?
    comparison_end_oid = params[:comparisonEndOid].present? ? params[:comparisonEndOid] : @pull_request.head_sha
    comparison_start_oid = params[:comparisonStartOid].present? ? params[:comparisonStartOid] : @pull_request.merge_base

    review = @pull_request.pending_review_for(user: current_user, head_sha: comparison_end_oid)

    if !review.persisted?
      return render json: { error: "#{review.errors.uniq.to_sentence}." }, status: :unprocessable_entity
    end

    submit_review = params[:submitBatch].to_s == "true"
    comment = nil

    if replying
      parent_comment = @pull_request.review_comments.where(id: params[:inReplyTo]).first
      return render json: { error: "#{MISSING_PARENT_ERROR}" }, status: :unprocessable_entity unless parent_comment

      thread = parent_comment.pull_request_review_thread
      return render json: { error: "#{MISSING_PARENT_ERROR}" }, status: :unprocessable_entity unless thread

      result = PullRequests::ReviewComments::Reply.create(
        repository: current_repository,
        pull_request: @pull_request,
        review: review,
        thread: thread,
        user: current_user,
        body: params[:text],
        submit_review: submit_review
      )
      case result
      when PullRequests::ReviewComments::Reply::Success
        comment = result.comment
        errors = nil
      when PullRequests::ReviewComments::Reply::Error
        comment = nil
        errors = result.errors
      else
        T.absurd(result)
      end

    else
      result = if current_repository.feature_flag_enabled?(:prx_comment_outside_the_diff, default: false)
        PullRequests::ReviewComments::Create.create_from_parameters(
          pull_request: @pull_request,
          review:,
          review_event: submit_review ? :comment : nil,
          body: params[:text],
          actor: current_user,
          destination_base_commit_oid: comparison_start_oid,
          destination_head_commit_oid: comparison_end_oid,
          only_changed_files: current_repository.feature_flag_enabled?(:cotd_comment_only_on_changed_files, default: false),
          parameters: {
            # New positional format requires underscore keys
            # We need to convert the clients snakeCase keys into underscore here.
            positioning: params[:positioning]&.to_unsafe_h&.transform_keys(&:underscore),

            # Previous blob positioning.
            side: symbolize_input_with_default(input: params[:side], default: :right),
            start_line: integerize_input_with_default(input: params[:startLine], default: nil),
            start_side: symbolize_input_with_default(input: params[:startSide], default: :right),
            subject_type: symbolize_input_with_default(input: params[:subjectType], default: :line),
            line: params[:line]&.to_i,
            path: params[:path],
          }.compact
        )
      else
        PullRequests::ReviewComments::Create.create(
          author: current_user,
          body: params[:text],
          diff_start_commit_oid: comparison_start_oid,
          diff_end_commit_oid: comparison_end_oid,
          diff_base_commit_oid: @pull_request.merge_base,
          line: params[:line].to_i,
          path: params[:path],
          pull_request: @pull_request,
          review: review,
          repository: current_repository,
          side: symbolize_input_with_default(input: params[:side], default: :right),
          start_line: integerize_input_with_default(input: params[:startLine], default: nil),
          start_side: symbolize_input_with_default(input: params[:startSide], default: :right),
          subject_type: symbolize_input_with_default(input: params[:subjectType], default: :line),
          submit_review: submit_review,
        )
      end

      case result
      when PullRequests::ReviewComments::Create::Success
        comment = result.comment
        thread = result.thread
        errors = nil
      when PullRequests::ReviewComments::Create::Error
        comment = nil
        thread = nil
        errors = result.errors
      else
        T.absurd(result)
      end
    end

    #TODO: implement the correct tags to log positioning failures
    # algorithm_tag = params[:algorithm] == "ignore-whitespace" ? "algorithm:ignore-whitespace" : "algorithm:vanilla"
    # outside_diff_tag = if @pull.repository.feature_enabled?(:comment_outside_the_diff)
    #   params[:expanded_diff] == "true" ? "outside_diff:true" : "outside_diff:false"
    # end
    # file_level_commenting_tag = params[:subject_type] == "file" ? "file_level:true" : "file_level:false"
    if errors&.any?
      errors.delete(:review_comments)
      # if errors.any? { |error| error.attribute == :line }
      #   GitHub.dogstats.increment("review.comment.position-error", tags: [algorithm_tag, outside_diff_tag, file_level_commenting_tag].compact)
      # end

      errors = errors.full_messages.map do |error|
        /oid is not part of the pull request/.match(error) ? OUT_OF_DATE_DIFF_ERROR : error
      end

      render json: { error: "#{errors.uniq.to_sentence}." }, status: :unprocessable_entity
    else

      GitHub.instrument "comment.create", user: current_user

      #TODO: include tags in logging once features are implemented: algorithm_tag, outside_diff_tag, file_level_commenting_tag
      tags = ["reply:#{replying ? 'true' : 'false' }"]
      GitHub.dogstats.increment("review.comment.created", tags: tags)

      limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
        repository: current_repository,
        user: current_user,
      )

      thread_mutation_data = PullRequests::PageData::ThreadMutation::Loader.load(
        current_user: current_user,
        thread: thread,
        comment: T.must(comment),
        limit_config: limit_config,
      )

      thread_mutation_payload = PullRequests::PageData::ThreadMutation::Payload.call(thread_mutation_data).as_json
      render json: thread_mutation_payload, status: :ok
    end
  end

  def add_comment_reaction
    comment = if params[:issueCommentId].present?
      @pull_request.issue.comments.find_by(id: params[:issueCommentId])
    elsif params[:reviewSummaryCommentId].present?
      @pull_request.reviews.find_by(id: params[:reviewSummaryCommentId])
    else
      @pull_request.review_comments.find_by(id: params[:commentId])
    end
    return render_404 unless comment

    reaction_content = params[:reaction]
    emotion = EMOTION_PLATFORM_ENUMS_TO_CONTENT[reaction_content]
    unless emotion
      return render json: { error: "Invalid reaction content" }, status: :unprocessable_entity
    end

    reaction = comment.react(actor: current_user, content: emotion)
    if !reaction.save
      return render json: { error: "Failed to add reaction" }, status: :unprocessable_entity
    end

    reaction_groups = PullRequests::PageData::Helpers::Reactable::Loader.async_reaction_groups(comment.reload, current_user).then do |groups|
      PullRequests::PageData::Helpers::Reactable::Payload.build_reaction_groups(groups)
    end.sync
    render json: { reactionGroups: reaction_groups }, status: :ok
  rescue => exception
    Failbot.report(exception)
    render json: { error: "Failed to add reaction" }, status: :internal_server_error
  end

  def remove_comment_reaction
    comment = if params[:issueCommentId].present?
      @pull_request.issue.comments.find_by(id: params[:issueCommentId])
    elsif params[:reviewSummaryCommentId].present?
      @pull_request.reviews.find_by(id: params[:reviewSummaryCommentId])
    else
      @pull_request.review_comments.find_by(id: params[:commentId])
    end
    return render_404 unless comment

    reaction_content = params[:reaction]
    emotion = EMOTION_PLATFORM_ENUMS_TO_CONTENT[reaction_content]
    unless emotion
      return render json: { error: "Invalid reaction content" }, status: :unprocessable_entity
    end

    comment.unreact(actor: current_user, content: emotion)

    reaction_groups = PullRequests::PageData::Helpers::Reactable::Loader.async_reaction_groups(comment.reload, current_user).then do |groups|
      PullRequests::PageData::Helpers::Reactable::Payload.build_reaction_groups(groups)
    end.sync
    render json: { reactionGroups: reaction_groups }, status: :ok
  rescue => exception
    Failbot.report(exception)
    render json: { error: "Failed to remove reaction" }, status: :internal_server_error
  end

  def symbolize_input_with_default(input:, default:)
    input.present? ? input.to_sym : default
  end

  def integerize_input_with_default(input:, default:)
    input.present? ? input.to_i : default
  end

  def abandon_review
    current_review = @pull_request.latest_pending_review_for(current_user)
    return render_404 if !current_review

    begin
      current_review.destroy_pending_comments
      render json: {
        message: "Your pending review comments have been discarded.", redirectUrl: pull_request_path(@pull_request)
      }, status: :ok
    rescue => exception
      Failbot.report!(exception)
      render json: { error: "Failed to delete pending comments for pending review." }, status: :internal_server_error
    end
  end

  def submit_review
    requested_event = params["event"]

    if ["approve", "reject", "request changes", "comment"].exclude?(requested_event)
      return render json: { error: "Invalid event" }, status: :unprocessable_entity
    end

    requested_event_allowed = case requested_event
    when "approve"
      @pull_request.allows_approval_reviews_from?(reviewer: current_user)
    when "reject", "request changes"
      @pull_request.allows_request_changes_reviews_from?(reviewer: current_user)
    end

    event = if requested_event_allowed
      requested_event
    else
      "comment"
    end

    current_review = @pull_request.latest_pending_review_for(current_user) ||
                      @pull_request.reviews.new(user_id: current_user.id, head_sha: params[:headSha])

    current_review.body = params[:body] unless current_review.body.nil? && params[:body].blank?

    if params[:headSha]
      current_review.head_sha = params[:headSha]
      current_review.merge_base_sha = @pull_request.find_best_merge_base_sha(head_sha: params[:headSha])
    end

    event_success = GitHub.dogstats.distribution_time("pull_request.review.submit", tags: ["event:#{event}"]) do
      case event
      when "approve"
        current_review.approve!
      when "reject", "request changes"
        current_review.request_changes!
      when "comment"
        current_review.comment!
      else
        return render json: { error: "Invalid event" }, status: :unprocessable_entity
      end
    end

    if !event_success
      error_msg = if current_review.halted?
        current_review.halted_because
      else
        "There was a problem submitting your review."
      end

      return render json: { error: error_msg }, status: :unprocessable_entity
    end

    success_msg = if @pull_request.open?
      "Your review was submitted successfully."
    else
      "Your review was submitted on a #{@pull_request.state.to_sym} pull request."
    end

    redirect_url = if current_review.show_in_timeline?
      current_review.permalink(include_host: false)
    else
      "#{pull_request_path(@pull_request)}"
    end

    render json: {
      message: success_msg,
      redirectUrl: redirect_url
    }, status: :ok
  end

  class ApiInvalidInputError < StandardError; end

  def apply_suggestions
    return render_404 unless @pull_request

    changes = Array(params[:changes]).map do |change|
      raise ApiInvalidInputError unless change.respond_to?(:fetch)
      {
        commentId: change.fetch("threadId", ""),
        path: change.fetch("path", ""),
        suggestion: change.fetch("suggestion", []),
      }
    end

    inputs = {
      pull_request: @pull_request,
      changes: changes,
      message: params[:message].to_s,
      current_oid: params[:currentOid],
      sign: true
    }

    # Doing one query to find all review comments that will be used later on by `PullRequestReviewComment::ApplySuggestedChange#call`
    review_comments = begin
      PullRequestReviewComment.find(changes.map { |c| c[:commentId] })
    rescue ActiveRecord::RecordNotFound => e
      return render json: { error: "One or more of the suggestion comments has been deleted." }, status: :not_found
    end

    review_comments_hash = Hash[review_comments.map { |c| [c.id, c] }]

    changes = changes.map do |change|
      {
        path: change[:path],
        suggestion: change[:suggestion],
        comment: review_comments_hash[change[:commentId].to_i]
      }
    end

    inputs.merge!(
      changes: changes,
      viewer: current_user,
      remote_ip: T.must(request).remote_ip,
      user_agent: T.must(request).user_agent
    )

    begin
      PullRequestReviewComment::ApplySuggestedChange.call(inputs)
    rescue PullRequestReviewComment::ApplySuggestedChange::NotFoundError => e
      return render json: { message: e.message }, status: :not_found
    rescue PullRequestReviewComment::ApplySuggestedChange::ForbiddenError => e
      return render json: { message: e.message }, status: :forbidden
    rescue PullRequestReviewComment::ApplySuggestedChange::UnprocessableError => e
      return render json: { message: e.message }, status: :unprocessable_entity
    end

    render json: { message: "The changes were successfully applied." }, status: :ok
  rescue GitHub::JSON::ParseError, StandardError
    render json: { message: "Sorry, the changes couldn't be applied." }, status: :unprocessable_entity
  end

  def hide_comment
    unless @current_comment && @current_comment.async_minimizable_by?(current_user).sync
      return render status: :unauthorized, json: { error: "User is not authorized to hide comment" }
    end

    comment_author = @current_comment.user || User.ghost
    if @current_comment.set_minimized(current_user, nil, params[:classifier], comment_author)
      render json: {
        commentDatabaseId: @current_comment.id,
        threadId: @current_comment.pull_request_review_thread.id,
        reason: @current_comment.minimized_reason,
      }, status: :ok
    else
      render status: :unprocessable_entity
    end
  end

  def unhide_comment
    unless @current_comment && @current_comment.async_unminimizable_by?(current_user).sync
      return render status: :unauthorized, json: { error: "User is not authorized to unhide comment" }
    end

    comment_author = @current_comment.user || User.ghost
    if @current_comment.set_unminimized(current_user, nil, comment_author)
      render json: {
        commentDatabaseId: @current_comment.id,
        threadId: @current_comment.pull_request_review_thread.id,
      }, status: :ok
    else
      render status: :unprocessable_entity
    end
  end

  def resolve_thread
    unless @review_thread.async_can_resolve(current_user).sync
      return render status: :unauthorized, json: { error: "User is not authorized to resolve the conversation" }
    end

    begin
      reason = if FeatureFlag.vexi.enabled?(:thread_resolution_reason, default: false) && @review_thread.copilot_code_review_thread?
        params[:resolution_reason].presence
      end
      @review_thread.resolve(resolver: current_user, resolution_reason: reason)
    rescue PullRequestReviewThread::ResolveReviewThreadError => e
      return render status: :unprocessable_entity, json: { error: e.message }
    end

    if @review_thread.errors.any?
      render status: :unprocessable_entity, json: { error: @review_thread.errors.full_messages.to_sentence }
    else
      render json: { message: "Thread was successfully resolved." }, status: :ok
    end
  end

  def unresolve_thread
    unless @review_thread.async_can_unresolve(current_user).sync
      return render status: :unauthorized, json: { error: ["User is not allowed to unresolve the conversation"] }
    end

    @review_thread.unresolve(unresolver: current_user)

    if @review_thread.errors.any?
      render status: :unprocessable_entity, json: { error: @review_thread.errors.full_messages.to_sentence }
    else
      render json: { message: "Thread was successfully unresolved." }, status: :ok
    end
  end

  def run_action_required_workflows
    unless current_repository.writable_by?(current_user)
      return render json: {
        error: "You do not have permission to approve pending workflows."
      }, status: :unprocessable_entity
    end

    workflow_run_ids = []
    @pull_request.action_required_check_suites(head_sha: @pull_request.head_sha).each do |check_suite|
      begin
        check_suite.rerequest(actor: current_user)
        workflow_run_ids << check_suite.workflow_run.id
      rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError, CheckSuite::AlreadyRerunningError, CheckSuite::DisabledWorkflowError, CheckSuite::NotRerequestableError => e
        GitHub.dogstats.increment("workflow.action_required_rerequest_failed", tags: ["error:#{e.class.name&.demodulize}"])
        return render json: {
          error: "Unable to re-run one or more workflows. Check if the workflows are already running, are more than 30 days old, or are disabled."
        }, status: :unprocessable_entity
      end
    end

    GlobalInstrumenter.instrument("workflow.action_required_approved", {
      pull_request_id: @pull_request.id,
      actor_id: T.must(current_user).id,
      repo_id: current_repository.id,
      workflow_run_ids: workflow_run_ids.sort!,
    })

    render json: {
      message: "Successfully approved pending workflows."
    }, status: :ok
  end

  def update_merge_box_user_preference
    preference_name = params[:preferenceName]
    preference = params[:preference]

    unless preference_name.present? && preference.present?
      return render json: {
        error: "Preference name and value must be provided."
      }, status: :unprocessable_entity
    end

    valid_preferences = {
      "status_checks_grouping_preference" => UserSettings::STATUS_CHECKS_GROUPING_PREFERENCE
    }

    unless valid_preferences.key?(preference_name) && valid_preferences[preference_name].include?(preference)
      return render json: {
        error: "Invalid preference name or value."
      }, status: :unprocessable_entity
    end

    current_user.settings.set!(preference_name.to_sym, preference)

    render json: {
      message: "Successfully updated preferences."
    }, status: :ok
  rescue => e
    render json: {
      error: "Failed to update preferences."
    }, status: :unprocessable_entity
  end

  def update_description
    return render_404 unless @pull_request.issue.can_modify?(current_user)
    return render_404 if blocked_by_owner?

    body = params[:body].to_s
    issue = @pull_request.issue

    if issue.update_body(body, current_user)
      description_data = PullRequests::PageData::Description::Loader.load(pull_request: @pull_request, current_user: current_user, cap_filter: cap_filter)
      payload = PullRequests::PageData::Description::Payload.call(description_data)
      render json: payload.to_json, status: :ok
    else
      render json: { error: issue.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def update_review_comment
    return render_404 if blocked_from_commenting?(@pull_request)

    current_comment = @pull_request.review_comments.find_by(id: params[:commentId])
    return render_404 if !current_comment
    return render_404 if !can_modify_commit_comment?(current_comment)

    if stale_model?(current_comment)
      return render status: :unprocessable_entity, json: { error: "This comment has been updated since you started editing. Please reload the page and try again." }
    end

    comment_body = if operation = TaskListOperation.from(params[:task_list_operation])
      operation.call(current_comment.body)
    else
      params[:body]
    end

    if comment_body
      PullRequests::ReviewComments::Update.update(
        comment: current_comment,
        body: comment_body,
        user: current_user,
      )
    end

    if !current_comment.valid?
      return render status: :unprocessable_entity, json: {
        error: "Could not edit comment."
      }
    end

    reloaded_comment = current_comment.reload
    raw_body_response_enabled = current_repository.feature_flag_enabled?(:pulls_update_review_comment_raw_body_response, default: false)

    render json: {
      bodyVersion: reloaded_comment.body_version,
      commentDatabaseId: reloaded_comment.id,
      threadId: reloaded_comment.pull_request_review_thread.id,
      body: raw_body_response_enabled ? reloaded_comment.body : reloaded_comment.body_text,
      bodyHTML: reloaded_comment.body_html(context: {
        viewer: current_user,
        cap_filter: cap_filter,
        unfurl_references: true,
      })
    }
  end

  def delete_review_comment
    return render_404 if current_repository.blocked_from_commenting?(user: current_user, commentable: @pull)

    comment = @pull_request.review_comments.find(params[:comment_id])
    return render_404 unless comment.deleteable_by?(current_user)

    result = PullRequests::ReviewComments::Delete.delete(
      actor: current_user,
      comment: comment,
      pull_request: @pull_request,
      repository: current_repository,
    )

    case result
    when PullRequests::ReviewComments::Delete::Success
      head :no_content
    when PullRequests::ReviewComments::Delete::Error
      render json: { error: result.errors.full_messages.to_sentence }, status: :unprocessable_entity
    else
      T.absurd(result)
    end
  end

  def update_whitespace_preference # rubocop:todo GitHub/UseRestfulActions
    whitespace_param = params[:w]

    if ["1", "0", 1, 0].exclude?(whitespace_param)
      return render json: { error: "Invalid whitespace preference" }, status: :unprocessable_entity
    end

    should_ignore_whitespace = ["1", 1].include?(whitespace_param)

    if should_ignore_whitespace
      @pull_request.set_ignore_whitespace_preference(current_user)
    else
      @pull_request.clear_ignore_whitespace_preference(current_user)
    end

    render json: { ignoreWhitespace: should_ignore_whitespace }, status: :ok
  end

  def update_show_change_groups_preference
    show_change_groups_param = params[:show_change_groups]

    if show_change_groups_param.nil?
      return render json: { error: "Invalid change groups preference" }, status: :unprocessable_entity
    end

    show_change_groups = params[:show_change_groups] == "true"

    current_user.settings.set!(:show_pr_change_groups, show_change_groups)

    render json: { showChangeGroups: show_change_groups }, status: :ok
  end

  # Width bounds for file tree panel (in pixels)
  # 0 means no preference/default, max is capped at reasonable screen width
  MIN_FILE_TREE_WIDTH = 0
  MAX_FILE_TREE_WIDTH = 2000

  def update_file_tree_width_preference
    return render json: { error: "File tree width must be provided" }, status: :unprocessable_entity unless params[:file_tree_width].present?

    width = params[:file_tree_width].to_i

    unless valid_file_tree_width?(width)
      return render json: { error: "File tree width must be between #{MIN_FILE_TREE_WIDTH} and #{MAX_FILE_TREE_WIDTH}" }, status: :unprocessable_entity
    end

    saved_width = width.zero? ? nil : width
    current_user.settings.set!(:pull_request_file_tree_width, saved_width)
    render json: { fileTreeWidth: saved_width }, status: :ok
  end

  def update_docked_panel_width_preference
    return render json: { error: "Docked panel width must be provided" }, status: :unprocessable_entity unless params[:docked_panel_width].present?

    width = params[:docked_panel_width].to_i

    begin
      current_user.settings.set!(:pull_request_docked_panel_width, width)
    rescue SettingsCollection::InvalidUpdate => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    render json: { dockedPanelWidth: width }, status: :ok
  end

  def submit_copilot_groups_feedback # rubocop:todo GitHub/UseRestfulActions
    access = PullRequests::Copilot::PullRequestGroupsAccess.new(actor: @current_user, current_repository: @repository)
    return render_404 unless access.can_view_generated_groups?

    feedback = params[:feedback]
    return render_404 if feedback.blank?
    PullRequests::ChangeGroupsFeedback.instrument_copilot_change_groups_feedback(
      request_id: GitHub.context[:request_id],
      organization_id: current_repository&.organization&.id,
      repository_id: current_repository.id,
      pull_request_id: @pull_request.id,
      head_sha: @pull_request.head_sha,
      base_sha: @pull_request.base_sha,
      analytics_tracking_id: current_user.analytics_tracking_id,
      feedback_type: feedback,
      feedback_choice: params[:feedback_choice],
      text_response: params[:text_response]
    )

    render json: { message: "Feedback submitted successfully." }, status: :ok
  end

  def generate_change_groups # rubocop:todo GitHub/UseRestfulActions
    access = PullRequests::Copilot::PullRequestGroupsAccess.new(actor: @current_user, current_repository: @repository)
    return render_404 unless access.can_view_generated_groups?

    return render_404 unless @current_user&.feature_flag_enabled?(:generate_groups_on_files_view, default: false)

    author = @pull_request.pull_request_copilot_attributions.first&.user || @pull_request.user

    return render_404 unless author

    PullRequests::ChangeGroups.generate_for(@pull_request, T.must(author))

    change_groups_data = PullRequests::PageData::ChangeGroupGeneration::Loader.load(
      comparison: @pull_request.pull_comparison,
      current_user: current_user,
      pull_request: @pull_request,
    )

    payload = PullRequests::PageData::ChangeGroupGeneration::Payload.call(change_groups_data)

    render json: payload.to_json, status: :ok
  end

  private

  sig { returns(PullRequests::Shared::Logger) }
  memoize def am_logger
    log = PullRequests::Shared::Logger.new(feature: "auto_merge", default_prefix: "gh.pull_request.auto_merge_request")
    log.append({ phase: "enable_auto_merge" })
    log
  end

  sig { params(message: String, context: T.untyped).void }
  def log_debug(message, **context)
    return unless FeatureFlag.vexi.enabled?(:am_mutations_logging, @pull_request&.repository, default: false)
    GitHub.logger.info(message, **context)
  end

  sig { params(message: String, context: T.untyped).void }
  def log_am_error(message, **context)
    return unless FeatureFlag.vexi.enabled?(:am_mutations_logging, @pull_request&.repository, default: false)
    GitHub.logger.error(message, **context)
  end

  sig { returns(T::Boolean) }
  memoize def prx_files_enabled?
    # we're not checking the feature preview here as we dont want to fail mutations if they have the FF enabled
    # if the user happened to have toggled the feature off in a different tab, mutations should still work
    current_user.feature_flag_enabled?(:prx_files, default: false)
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def use_repository_cluster_replicas(&block)
    use_replica_clusters([ApplicationRecord::Repositories], &block)
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def use_user_cluster_replicas(&block)
    use_replica_clusters([ApplicationRecord::Mysql1], &block)
  end

  sig { void }
  def require_prx_files
    if !prx_files_enabled?
      render_404
    end
  end

  sig { void }
  def load_pull_request
    @pull_request = PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
    render_404 if @pull_request.nil?

    if @pull_request && FeatureFlag.vexi.enabled?(:prs_push_pr_id_to_failbot, current_repository, default: false)
      Failbot.push("gh.pull_request.id": @pull_request.id)
    end

    @pull_request
  end

  sig { void }
  def load_comment
    @current_comment = @pull_request.review_comments.find_by(id: params[:commentId])
    if @current_comment.nil?
      render_404
    end
  end

  sig { params(comment: ::IssueComment).returns(T.nilable(PullRequests::PageData::IssueComments::Payload::IssueComment)) }
  def build_issue_comment_payload(comment)
    # Build reaction groups
    reaction_groups = PullRequests::PageData::Helpers::Reactable::Loader
      .async_reaction_groups(comment, current_user).sync

    # Build the IssueComment struct that Payload expects
    issue_comment = PullRequests::PageData::IssueComments::Loader::IssueComment.new(
      id: comment.id.to_s,
      comment: comment,
      author_association: comment.author_association.to_sym.to_s.upcase,
      author_avatar_url: comment.user&.primary_avatar_url,
      author_login: comment.user&.display_login || "ghost",
      body_html: comment.body_html(context: { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }),
      url: comment.url,
      viewer_can_react: current_user ? comment.viewer_can_react?(current_user) : false,
      reaction_groups: reaction_groups,
    )

    # Use the Payload class to transform it to the expected format
    PullRequests::PageData::IssueComments::Payload.call([issue_comment]).first
  end

  sig { void }
  def load_review_thread
    @review_thread = PullRequestReviewThread.includes(:pull_request).find_by(id: params[:threadId])
    if @review_thread.nil?
      render_404
    end
  end

  # Overrides AbstractRepositoryController's default false return value
  sig { returns(T::Boolean) }
  def route_supports_advisory_workspaces?
    # The following actions are not supported for advisory workspaces
    !%w(merge).include?(action_name)
  end

  sig { params(via: String).returns(T::Hash[Symbol, String]) }
  def request_reflog_data(via)
    super(via).merge({ pr_author_login: @pull_request.safe_user.display_login })
  end

  sig { params(author_email: T.nilable(String)).returns(T.nilable(T::Boolean)) }
  def invalid_author_email?(author_email)
    # You can only choose an email if it's a non-enterprise instance at the moment
    return true if author_email && !GitHub.choose_commit_email_enabled?

    # Only the pull request author is allowed to override the email for the squash commit.
    # See: https://github.com/github/github/blob/0f6795195019f305a2a6c4bc0a360fa8e8f4de18/packages/pull_requests/app/models/pull_request/merge.rb#L435
    # So, in general, we will only pass the author_email from the client for :merge or if the author is allowed to select the email.

    # Validations further down in the chain call the same validations and throw in more unexpected ways, so we shouldn't try to skip this.
    author_email && !current_user&.author_emails.include?(author_email)
  end

  def auto_merge_content_authorization_required
    authorize_content(:pull_request, action_to_authorize: :auto_merge, repo: current_repository)
  end

  def update_content_authorization_required
    authorize_content(:pull_request, action_to_authorize: :update, repo: current_repository)
  end

  def pull_request_comment_update_content_authorization_required
    authorize_content(:pull_request_comment, action_to_authorize: :update, repo: current_repository)
  end

  def pull_request_comment_create_content_authorization_required
    authorize_content(:pull_request_comment, action_to_authorize: :create, repo: current_repository)
  end

  def set_sticky_merge_method(merge_method)
    case merge_method
    when :rebase
      @pull_request.base_repository.set_sticky_merge_method(current_user, "rebase")
    when :squash
      @pull_request.base_repository.set_sticky_merge_method(current_user, "squash")
    when :merge
      @pull_request.base_repository.set_sticky_merge_method(current_user, "merge_commit")
    end
  rescue => e
    Failbot.report(e)
  end

  sig { params(merge_method: T.nilable(String)).returns(Symbol) }
  def determine_merge_method(merge_method)
    if merge_method.present?
      return merge_method.downcase.to_sym
    end

    allowable_merge_methods = @pull_request.async_allowable_merge_methods(actor: current_user).sync

    if allowable_merge_methods.merge_commit.allowed?
      :merge
    elsif allowable_merge_methods.squash_merge.allowed?
      :squash
    elsif allowable_merge_methods.rebase_merge.allowed?
      :rebase
    else
      # TODO: Handle no allowable method more gracefully
      :merge
    end
  end

  def render_status(status, message, metadata: nil)
    case status
    when :ok
      GitHub.dogstats.histogram("pull_request.merged.requested_reviewers.count", @pull_request.review_requests.pending.size)
      render json: { message: message }, status: status
    else
      GitHub.dogstats.increment("pull_request", tags: ["action:merge", "error:invalid"])
      render json: { error: message, metadata: }, status: status
    end
  end

  sig { void }
  def render_rate_limited_response
    render status: :too_many_requests, json: { error: RATE_LIMIT_REACHED }
  end

  def handle_merge(feature, merge_method, source = nil, include_email: true)
    validation_result = validate_commit_parameters(merge_method.to_sym)
    return validation_result if validation_result.present?

    case merge_result = PullRequests::Merge.call(
        pull_request: @pull_request,
        user: T.must(current_user),
        commit_title: params[:commitTitle],
        commit_body: params[:commitMessage],
        commit_author_email: include_email ? params[:authorEmail] : nil,
        reflog_data: request_reflog_data("pull request merge button"),
        expected_head_sha: params[:headSha],
        method: merge_method.to_sym,
        source: source,
        feature:,
      )

    when PullRequests::Merge::Success
      message = "Pull request is merged."
      status = :ok
    when PullRequests::Merge::Failure
      message = if merge_result.code == :repository_rule_violation
        "Merging was blocked due to rule violation errors."
      else
        merge_result.error_message
      end

      status = :unprocessable_entity
    else
      T.absurd(merge_result)
    end

    { message: message, status: status }
  rescue Git::Ref::HookFailed => e
    message = "Merging was blocked by pre-receive hooks."
    status = :unprocessable_entity

    { message: message, status: status }
  rescue GitRPC::Timeout => e
    message = "Merging failed due to a timeout. Please try again."
    status = :gateway_timeout

    { message: message, status: status }
  end

  def validate_commit_parameters(merge_method)
    repository = @pull_request.base_repository

    return nil unless repository.prx_merge_improvements?

    message_title, message, _ = @pull_request.determine_merging_message(merge_method, params[:commitTitle], params[:commitMessage])
    commit_message = if message_title.present? && message.present?
      "#{message_title}\n\n#{message}"
    elsif message_title.present?
      message_title
    elsif message.present?
      message
    else
      nil
    end

    rule_engine_event = RuleEngine::Events::MergeBoxConfirmationEvent.new(
      repository,
      T.must(current_user),
      qualified_ref_name: @pull_request.qualified_base_ref_name,
      before_oid: @pull_request.base_sha,
      allow_empty_commit_message: merge_method == :rebase,
      commit_message:,
    )

    rule_engine_event_result = RuleEngine::GenericEvaluator.evaluate_rules(rule_engine_event)

    errors = rule_engine_event_result.filter_map do |rule_suite|
      next if rule_suite.action_permitted?

      rule_suite.failure_messages(prefix: nil, exclude_violations: true, include_bypassed: false)
    end.flatten

    return {
      message: "Merging was blocked due to commit metadata restriction violation errors.",
      status: :unprocessable_entity,
      metadata: {
        ruleErrors: errors
      }
    } if errors.any?

    nil
  end

  def valid_file_tree_width?(width)
    width >= MIN_FILE_TREE_WIDTH && width <= MAX_FILE_TREE_WIDTH
  end
end
