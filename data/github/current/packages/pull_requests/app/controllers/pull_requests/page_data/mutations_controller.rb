# rubocop:disable GitHub/UseRestfulActions
# typed: true
# frozen_string_literal: true

class PullRequests::PageData::MutationsController < AbstractRepositoryController
  include GitHub::RateLimitedRequest
  include JsonDependency
  include VerifiedFetchDependency
  include ::MergeQueues::SharedControllerMethods

  allow_verified_fetch

  before_action :login_required
  before_action :require_xhr
  before_action :load_pull_request
  before_action :parse_json_params
  before_action :auto_merge_content_authorization_required, only: [:enable_auto_merge, :disable_auto_merge]
  before_action :update_content_authorization_required, only: [
    :delete_head_ref,
    :restore_head_ref,
    :merge,
    :mark_ready_for_review,
    :update_pull_request_branch
  ]
  skip_before_action :set_repo_as_hovercard_subject
  before_action :dequeue_pull_request_authorization_required, only: [:dequeue_pull_request]
  before_action :merge_queue_required, only: [:dequeue_pull_request]

  WRITE_RATE_LIMIT = 60

  rate_limit_requests \
    if: :logged_in?,
    max: WRITE_RATE_LIMIT,  # per minute
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, # 1.minute
    key: :default_rate_limit_key,
    at_limit: :render_rate_limited_response

  rescue_from_timeout_without_replay only: [:merge] do
    T.bind(self, PullRequests::PageData::MutationsController)

    GitHub.dogstats.increment("pull_requests.merge_timeout_rescued")

    orchestration = PullRequests::Orchestrations::Merge.active.find_by(pull_request_id: @pull_request&.id)
    orchestration&.end_orchestration(:failed, "merge timed out")

    render json: { error: "Merge attempt timed out." }, status: :gateway_timeout
  end

  def enable_auto_merge
    return render_404 unless mergebox_react_partial_enabled?
    return render_404 unless current_user_can_push?

    author_email = params[:authorEmail].presence || current_user.git_author_email
    if current_user.is_enterprise_managed?
      return render_404 unless current_user.profile_email == author_email
      email = current_user.emails.find_by(email: current_user.email)
    else
      return render_404 unless email = current_user.emails.find_by(email: author_email)
    end

    can_enable_auto_merge_result = @pull_request.can_enable_auto_merge(actor: current_user)

    merge_queue = MergeQueue.for(repository: @pull_request.base_repository, branch: @pull_request.base_ref)

    if can_enable_auto_merge_result.allowed? || merge_queue
      merge_method = determine_merge_method(params[:mergeMethod])

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
    elsif can_enable_auto_merge_result.reason&.include?("clean status")
      GitHub.dogstats.increment("pull_request.merge_attempt", tags: ["action:enable_auto_merge"])

      merge_method = determine_merge_method(params[:mergeMethod])

      # Omit `commit_author_email` until we enable selecting the commit author (see: https://github.com/github/pull-requests/issues/8489)
      handle_merge_response = handle_merge(merge_method, include_email: false)
      message = handle_merge_response[:message]
      status = handle_merge_response[:status]
      metadata = handle_merge_response[:metadata]

      set_sticky_merge_method(merge_method)
      render_status(status, message, metadata:)
    else
      render json: { error: can_enable_auto_merge_result.reason }, status: :unprocessable_entity
    end

  rescue AutoMergeRequest::Invalid => e
    render json: { error: "Failed enabling auto-merge for pull request" }, status: :unprocessable_entity
  end

  def disable_auto_merge
    return render_404 unless mergebox_react_partial_enabled?
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
    render  json: { error: "Failed disabling auto-merge for pull request" }, status: :unprocessable_entity
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
  rescue => exception # rubocop:disable Lint/GenericRescue
    Failbot.report!(exception)
    render json: { error: "Pull request failed to be marked as ready for review" }, status: :internal_server_error
  end

  def merge
    return render_404 unless mergebox_react_partial_enabled?
    return render_404 unless current_user_can_push?

    if invalid_author_email?(params[:authorEmail])
      GitHub.dogstats.increment("pull_request", tags: ["action:merge", "error:invalid"])
      return render json: { error: "Invalid email for web commit." }, status: :unprocessable_entity
    end

    allowed_merge_methods = @pull_request.async_allowable_merge_methods.sync

    merge_method = determine_merge_method(params[:mergeMethod])

    merge_method_setting = case merge_method
    when :merge
      allowed_merge_methods.merge_commit
    when :squash
      allowed_merge_methods.squash_merge
    when :rebase
      allowed_merge_methods.rebase_merge
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

      handle_merge_response = handle_merge(merge_method, source)
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
    return render_404 unless mergebox_react_partial_enabled?
    return render_404 unless current_user_can_push?

    dequeued_entry = merge_queue.entry_for(pull_request: @pull_request)
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

  def update_pull_request_branch
    return render_404 unless mergebox_react_partial_enabled?

    update_method = params[:updateMethod]&.downcase == "rebase" ? "rebase" : "merge"
    result = PullRequests::UpdateBranch.execute(pull_request: @pull_request, user: T.must(current_user), update_method:, expected_head_oid: params[:expectedHeadOid])

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
      Failbot.push_sensitive("gh.pull_requests.re_request_reviews_validation_errors" => @pull_request.errors.full_messages.to_sentence)
      render json: { error: "Failed to re-request review." }, status: :unprocessable_entity
    end
  end

  def re_request_review_from_team
    if params[:teamName].blank?
      return render json: { error: "Team name is required." }, status: :unprocessable_entity
    end
    # note: the team name should not include the @ at the beginning!
    reviewer = Team.find_by_combined_slug(params[:teamName])
    return render_404 unless reviewer.present?
    if @pull_request.request_review_from(reviewers: [reviewer], actor: current_user, re_request: true, append: true)
      render json: { message: "Review request was successfully re-requested." }, status: :ok
    else
      Failbot.push_sensitive("gh.pull_requests.re_request_reviews_validation_errors" => @pull_request.errors.full_messages.to_sentence)
      render json: { error: "Failed to re-request review." }, status: :unprocessable_entity
    end
  end

  private

  sig { returns(T::Boolean) }
  memoize def mergebox_react_partial_enabled?
    current_repository.feature_enabled?(:mergebox_react_partial) || current_user.feature_enabled?(:mergebox_react_partial)
  end

  sig { void }
  def load_pull_request
    @pull_request = PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
    render_404 if @pull_request.nil?
    @pull_request
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
    author_email && (!GitHub.choose_commit_email_enabled? || !current_user&.author_emails.include?(author_email))
  end

  def auto_merge_content_authorization_required
    authorize_content(:pull_request, action_to_authorize: :auto_merge, repo: current_repository)
  end

  def update_content_authorization_required
    authorize_content(:pull_request, action_to_authorize: :update, repo: current_repository)
  end

  def dequeue_pull_request_authorization_required
    authorize_content(:pull_request, action_to_authorize: :dequeue, repo: current_repository)
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

  def determine_merge_method(merge_method)
    allowed_merge_methods = @pull_request.async_allowable_merge_methods.sync

    if merge_method.present?
      merge_method.downcase.to_sym
    elsif allowed_merge_methods.merge_commit.allowed?
      :merge
    else
      :squash
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

  def handle_merge(merge_method, source = nil, include_email: true)
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
      source: source
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
  end

  def validate_commit_parameters(merge_method)
    repository = @pull_request.base_repository

    return nil unless repository.prx_merge_improvements?

    message_title, message, _ = @pull_request.determine_merging_message(merge_method, params[:commitTitle], params[:commitMessage])

    rule_engine_event = RuleEngine::Events::MergeBoxConfirmationEvent.new(
      repository,
      T.must(current_user),
      qualified_ref_name: @pull_request.qualified_base_ref_name,
      before_oid: @pull_request.base_sha,
      commit_message: "#{message_title}\n\n#{message}",
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
end
