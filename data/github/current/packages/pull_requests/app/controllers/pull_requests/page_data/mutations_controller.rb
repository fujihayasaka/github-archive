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
    :delete_head_ref,
    :restore_head_ref,
    :merge,
    :mark_ready_for_review,
    :update_pull_request_branch
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
    :unhide_comment
  ]
  before_action :load_review_thread, only: [:resolve_thread, :unresolve_thread]
  before_action :load_comment, only: [:hide_comment, :unhide_comment]
  before_action :pull_request_comment_create_content_authorization_required, only: [:create_review_comment]
  before_action :pull_request_comment_update_content_authorization_required, only: [:update_review_comment]

  prepend_around_action :use_repository_cluster_replicas, only: [:submit_review]

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

    # Only the pull request author is allowed to override the email for the squash commit.
    # This validation works for squash only if the pull request author is selecting an email.
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
      # For merge_queue, params[:mergeMethod] is either GROUP or SOLO
      # For all other cases, params[:mergeMethod] is either MERGE, SQUASH, or REBASE
      # This is due to the way auto-merge is modeled.
      merge_method = determine_merge_method(params[:mergeMethod])

      if @pull_request.base_repository.feature_enabled?(:pass_merge_queue_merge_method) && merge_queue
        config = MergeQueues.configuration_for(merge_queue)
        merge_method = config.merge_method.serialize
      end

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
      result = if params[:positioning].present? && current_repository.feature_enabled?(:pull_requests_create_new_positioning)
        PullRequests::ReviewComments::Create.create_with_position(
          author: current_user,
          body: params[:text],
          diff_start_commit_oid: comparison_start_oid,
          diff_end_commit_oid: comparison_end_oid,
          diff_base_commit_oid: @pull_request.merge_base,
          pull_request: @pull_request,
          review:,
          repository: current_repository,
          submit_review:,
          positioning: params[:positioning].to_unsafe_h,
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
          side: params[:side].to_sym,
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
    comment = @pull_request.review_comments.find_by(id: params[:commentId])
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
    comment = @pull_request.review_comments.find_by(id: params[:commentId])
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
    rescue => exception # rubocop:disable Lint/GenericRescue
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


    event_success = case event
    when "approve"
      current_review.approve!
    when "reject", "request changes"
      current_review.request_changes!
    when "comment"
      current_review.comment!
    else
      return render json: { error: "Invalid event" }, status: :unprocessable_entity
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
      @review_thread.resolve(resolver: current_user)
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

    render json: {
      commentDatabaseId: current_comment.id,
      threadId: current_comment.pull_request_review_thread.id,
      body: current_comment.reload.body_text,
      bodyHTML: current_comment.body_html(context: {
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

  private

  sig { returns(T::Boolean) }
  memoize def mergebox_react_partial_enabled?
    current_user.feature_enabled?(:new_merge_box_ga) ||
    current_repository.feature_enabled?(:mergebox_react_partial) || current_user.feature_enabled?(:mergebox_react_partial)
  end

  sig { returns(T::Boolean) }
  memoize def prx_files_enabled?
    current_repository.feature_enabled?(:prx_files) || current_user.feature_enabled?(:prx_files)
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def use_repository_cluster_replicas(&block)
    use_replica_clusters([ApplicationRecord::Repositories], &block)
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
    @pull_request
  end

  sig { void }
  def load_comment
    @current_comment = @pull_request.review_comments.find_by(id: params[:commentId])
    if @current_comment.nil?
      render_404
    end
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
    authorize_content(:pull_request_comment,  action_to_authorize: :update, repo: current_repository)
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
    if current_repository.feature_enabled?(:fix_default_merge_method)
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
    else
      allowable_merge_methods = @pull_request.async_allowable_merge_methods(actor: current_user).sync

      if merge_method.present?
        merge_method.downcase.to_sym
      elsif allowable_merge_methods.merge_commit.allowed?
        :merge
      else
        :squash
      end
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
end
