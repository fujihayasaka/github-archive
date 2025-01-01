# typed: true
# frozen_string_literal: true

class PullRequestReviewCommentsController < GitContentController
  include CommentsHelper
  include PullRequests::DatabaseSelection
  include PullRequests::Copilot::CodeReview::ControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:suggestion_button]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:edit_form]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true, only: [:edit_form]

  MISSING_PARENT_ERROR = "The comment you are replying to has been deleted."
  OUT_OF_DATE_DIFF_ERROR = "This diff is outdated, please refresh and try again."

  before_action :login_required
  before_action :load_current_pull_request
  before_action :ensure_current_user_not_blocked, only: [:create]
  before_action :content_authorization_required, only: [:create, :update]

  prepend_around_action :use_repository_cluster_replicas, only: [:create]
  prepend_around_action :use_user_cluster_replicas, only: [:create]

  # Create a PullRequestReviewComment, and required PullRequestReview and/or
  # PullRequestReviewThread if necessary
  def create
    result = data = comment_database_id = nil
    body = params[:comment] && params[:comment][:body]
    replying = params[:in_reply_to].present?
    already_has_review = !!@pull.reviews.with_pending_state.where(user_id: current_user.id).first
    review = @pull.pending_review_for(user: current_user, head_sha: params[:comparison_end_oid])

    if !review.persisted?
      if request.xhr?
        return render status: 422, json: { errors: review.errors.uniq.to_sentence }
      else
        return redirect_to pull_request_path(@pull)
      end
    end

    replying_on_conversation_tab_without_pending_review = params[:on_conversation_tab].present? && !already_has_review
    submit_review = params[:single_comment].present? || replying_on_conversation_tab_without_pending_review

    comment = nil

    if replying
      parent = find_parent(params[:in_reply_to])
      return handle_missing_parent unless parent

      thread = parent.pull_request_review_thread
      return handle_missing_parent unless thread

      # we need to know if thread is a conversation before adding a new comment
      is_conversation = thread.conversation?

      result = PullRequests::ReviewComments::Reply.create(
        repository: current_repository,
        pull_request: @pull,
        review:,
        thread:,
        user: current_user,
        body:,
        submit_review:
      )

      case result
      when PullRequests::ReviewComments::Reply::Success
        comment = result.comment
        errors = nil

        if should_chat_within_this_thread?(comment:, parent:)
          PullRequests::Copilot::CodeReview::ThreadReplyProcessor.process(
            actor_id: current_user.id,
            copilot: T.must(T.must(pull_request_reviewer_app).bot),
            pull_request_id: @pull.id,
            pull_request_review_comment_id: comment.id,
            pull_request_review_id: review.id,
            pull_request_review_thread_id: thread.id,
            repository_id: current_repository.id,
          )
        end
      when PullRequests::ReviewComments::Reply::Error
        # This is exploiting the untyped duck type of an object responding to #errors.
        # TODO: This should be flow controlled here.
        comment = nil
        errors = result.errors
      else
        T.absurd(result)
      end
    else
      result = PullRequests::ReviewComments::Create.create(
        author: current_user,
        body: body,
        diff_start_commit_oid: params[:comparison_start_oid],
        diff_end_commit_oid: params[:comparison_end_oid],
        diff_base_commit_oid: params[:comparison_base_oid],
        line: params[:line].to_i,
        path: params[:path],
        pull_request: @pull,
        review: review,
        repository: current_repository,
        side: params[:side].to_sym,
        start_line: integerize_input_with_default(input: params[:start_line], default: nil),
        start_side: symbolize_input_with_default(input: params[:start_side], default: :right),
        subject_type: symbolize_input_with_default(input: params[:subject_type], default: :line),
        submit_review: submit_review,
      )

      case result
      when PullRequests::ReviewComments::Create::Success
        comment = result.comment
        thread = result.thread
        errors = nil
      when PullRequests::ReviewComments::Create::Error
        # This is exploiting the untyped duck type of an object responding to #errors
        # and the error handling of the object errors in the code below.

        # TODO: This should be flow controlled here / errors should overall be more
        # granularly handled by the controller than they are.
        comment = nil
        thread = nil
        errors = result.errors
      else
        T.absurd(result)
      end
    end

    algorithm_tag = params[:algorithm] == "ignore-whitespace" ? "algorithm:ignore-whitespace" : "algorithm:vanilla"
    outside_diff_tag = if @pull.repository.feature_flag_enabled?(:comment_outside_the_diff, default: false)
      params[:expanded_diff] == "true" ? "outside_diff:true" : "outside_diff:false"
    end
    file_level_commenting_tag = params[:subject_type] == "file" ? "file_level:true" : "file_level:false"

    if errors&.any?
      errors.delete(:review_comments)
      if errors.any? { |error| error.attribute == :line }
        GitHub.dogstats.increment("review.comment.position-error", tags: [algorithm_tag, outside_diff_tag, file_level_commenting_tag].compact)
      end

      errors = errors.full_messages.map do |error|
        /oid is not part of the pull request/.match(error) ? OUT_OF_DATE_DIFF_ERROR : error
      end

      if request.xhr?
        render status: 422, json: { errors: errors.uniq.to_sentence }
      else
        redirect_to pull_request_path(review.pull_request)
      end

      return
    end

    GitHub.instrument "comment.create", user: current_user

    tags = ["reply:#{replying ? 'true' : 'false' }", algorithm_tag, outside_diff_tag, file_level_commenting_tag].compact
    GitHub.dogstats.increment("review.comment.created", tags: tags)

    instrument_saved_reply_use(params[:saved_reply_id], "pull_request_review_comment")

    if request.xhr?
      respond_to do |format|
        format.json do
          json = {}

          json["pendingReviewCommentsCount"] = review.review_comments.with_pending_state.size

          # Replying to a thread - render just the reply comment to append to the existing thread.
          # If the thread was not a conversation we render the whole thread.
          if replying && is_conversation
            json[:inline_comment] = render_to_string(
              PullRequests::ReviewCommentComponent.new(
                pull_request_review_comment: comment,
                pull_request: @pull,
                comment_context: params[:comment_context]
              ), formats: [:html], layout: false
            )
          else
            threads = [
              DeprecatedPullRequestReviewThread.new(
                pull: @pull,
                pull_comparison: comment&.loaded_pull_request_review_thread.original_pull_request_comparison,
                path: comment&.loaded_pull_request_review_thread.path,
                position: comment&.loaded_pull_request_review_thread.original_position,
                comments: [comment],
              ),
            ]

            CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: @pull)

            rendering_on_files_tab = true

            # The conditional here is to limit the potential unexpected side-effects to a fix that is specific to Code Scanning (DFA) comment replies.
            if replying && (thread.code_scanning? || thread.code_quality?)
              rendering_on_files_tab = params[:comment_context] == "diff"
              json[:replace_container] = true
            end

            # Render entire thread with line comment form.
            json[:inline_comment_thread] = render_to_string(
              partial: "diff/review_threads",
              formats: [:html],
              object: threads,
              locals: {
                rendering_on_files_tab:,
              },
            )
          end

          render json: json
        end
      end
    else
      redirect_to_comment_anchor(comment, params[:comment_context])
    end
  end

  def update
    if blocked_from_commenting?(@pull)
      access_denied
      return
    end

    comment = current_comment
    if can_modify_commit_comment?(comment)
      # prevent updates from stale data
      if stale_model?(comment)
        return render_stale_error(model: comment, error: "Could not edit comment. Please try again.", path: pull_request_path(@pull, @pull.repository))
      end

      comment_body = if operation = TaskListOperation.from(params[:task_list_operation])
        operation.call(comment.body)
      else
        params[:pull_request_review_comment][:body]
      end

      if comment_body
        PullRequests::ReviewComments::Update.update(
          comment: comment,
          body: comment_body,
          user: current_user,
        )
      end

      respond_to do |format|
        format.json do
          render json: {
            "source" => comment.body,
            "body" => comment.body_html(context: { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }),
            "newBodyVersion" => comment.body_version,
            "editUrl" => show_comment_edit_history_path(comment.global_relay_id),
          }
        end

        format.html do
          unless comment.valid?
            flash[:error] = "Could not edit comment."
          end

          redirect_to_comment_anchor(comment, params[:comment_context])
        end
      end
    else
      access_denied
    end
  end

  def destroy
    if blocked_from_commenting?(@pull)
      access_denied
      return
    end

    comment = current_comment
    if comment.deleteable_by?(current_user)
      result = PullRequests::ReviewComments::Delete.delete(
        repository: current_repository,
        pull_request: @pull,
        comment: comment,
        actor: current_user,
      )

      case result
      when PullRequests::ReviewComments::Delete::Success
        pull_request = result.pull_request
      when PullRequests::ReviewComments::Delete::Error
        # This is exploiting the untyped duck type of an object responding to #errors
        # and the error handling of the object errors in the code below.

        # TODO: This should be flow controlled here / errors should overall be more
        # granularly handled by the controller than they are.
        errors = result.errors
      else
        T.absurd(result)
      end

      respond_to do |format|
        format.html do
          redirect_to pull_request_path(@pull)
        end
        format.json do
          review = comment
            .pull_request
            .reviews
            .with_pending_state
            .find_by(user_id: current_user.id, id: comment.pull_request_review&.id)
          render json: {
            "pendingReviewCommentsCount" => review.nil? ? 0 : review.review_comments.with_pending_state.size
          }
        end
      end
    else
      access_denied
    end
  end

  def suggestion_button # rubocop:todo GitHub/UseRestfulActions
    selection = if comment_id = params[:comment_id].presence || params[:in_reply_to].presence
      comment = find_parent(comment_id)

      PullRequestReviewComment::SuggestedChangeSelection.from_persisted_comment(comment)
    else
      PullRequestReviewComment::SuggestedChangeSelection.new(
        pull: @pull,
        path: params[:path],
        start_commit_oid: params[:start_commit_oid],
        end_commit_oid: params[:end_commit_oid],
        base_commit_oid: params[:base_commit_oid],
        start_line: params[:start_line].presence&.to_i,
        start_side: params[:start_side],
        line: params[:end_line].to_i,
        side: params[:end_side],
      )
    end

    respond_to do |format|
      format.html do
        render(Comments::SuggestionButtonComponent.new(
          textarea_id: params[:textarea_id],
          outdated: selection.outdated?,
          lines: selection.lines,
          contains_deletions: selection.contains_deletions?,
          disabled: selection.disabled?,
          missing_commit: !selection.valid_commits?,
          empty_selection: selection.lines.empty?,
          pull_request: @pull
        ), layout: false)
      end
    end
  end

  def actions # rubocop:todo GitHub/UseRestfulActions
    permission = Platform::Authorization::Permission.new(viewer: current_user, origin: Platform::ORIGIN_INTERNAL)
    comment = Platform::Helpers::NodeIdentification.typed_object_from_id(
      [Platform::Objects::PullRequestReviewComment, Platform::Objects::PullRequestReview],
      params[:id], permission: permission)

    render partial: "comments/review_comment_actions", locals: {
      tab: params[:tab].to_sym,
      comment: comment
    }
  rescue Platform::Errors::NotFound
    render_404
  end

  def show
    if current_comment.pending? && current_comment.user != current_user
      return render_404
    end

    render comment_variant_component.new(pull_request_review_comment: current_comment, pull_request: @pull, render_minimized: true), formats: [:html], layout: false
  end

  def minimize # rubocop:todo GitHub/UseRestfulActions
    unless current_comment && current_comment.async_minimizable_by?(current_user).sync
      return head :unprocessable_entity
    end

    comment_author = current_comment.user || User.ghost
    if current_comment.set_minimized(current_user, nil, params[:classifier], comment_author)
      render comment_variant_component.new(pull_request_review_comment: current_comment, pull_request: @pull, render_minimized: false), formats: [:html], layout: false
    else
      head :unprocessable_entity
    end
  end

  def unminimize # rubocop:todo GitHub/UseRestfulActions
    unless current_comment && current_comment.async_unminimizable_by?(current_user).sync
      return head :unprocessable_entity
    end

    comment_author = current_comment.user || User.ghost
    if current_comment.set_unminimized(current_user, nil, params[:classifier], comment_author)
      render comment_variant_component.new(pull_request_review_comment: current_comment, pull_request: @pull, render_minimized: false), formats: [:html], layout: false
    else
      head :unprocessable_entity
    end
  end

  def edit_form # rubocop:todo GitHub/UseRestfulActions
    comment = current_comment

    unless can_modify_commit_comment?(comment)
      head :forbidden
      return
    end

    render Comments::EditForm::EditFormComponent.new(
      comment: comment,
      comment_context: params[:comment_context],
      textarea_id: params[:textarea_id],
      slash_commands_enabled: current_user.slash_commands_enabled?,
      slash_commands_surface: SlashCommands::PULL_REQUEST_SURFACE,
      current_repository: current_repository
    ), layout: false
  end

  private

  def ensure_current_user_not_blocked
    if blocked_from_commenting?(@pull)
      redirect_to pull_request_path(@pull)
    end
  end

  # Private: Handle the case where parent comment has been deleted out from
  # under a reply attempt
  def handle_missing_parent
    if request.xhr?
      render status: 422, json: {
        errors: [MISSING_PARENT_ERROR],
      }
    else
      flash[:error] = MISSING_PARENT_ERROR
      redirect_to pull_request_path(@pull)
    end
  end

  sig { params(in_reply_to: T.any(String, Integer)).returns(T.nilable(PullRequestReviewComment)) }
  def find_parent(in_reply_to)
    @pull.review_comments.where(id: in_reply_to).first
  end

  memoize def current_comment
    @pull.review_comments.find(params[:id])
  end

  def load_current_pull_request
    @pull = current_repository.issues.find_by_number(params[:pull_id].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return render_404 unless @pull

    @comparison = @pull.comparison
  end

  def authorized?
    params[:action] == "create" ? (logged_in? && super) : super
  end

  def redirect_to_comment_anchor(comment, comment_context)
    url = case comment_context
    when "discussion"
      "#{pull_request_path(@pull)}#discussion_r#{comment.id}"
    else
      "#{pull_request_path(@pull)}/files#r#{comment.id}"
    end
    redirect_to url
  end

  def content_authorization_required
    authorize_content(:pull_request_comment, repo: current_repository)
  end

  def route_supports_advisory_workspaces?
    true
  end

  def symbolize_input_with_default(input:, default:)
    input.present? ? input.to_sym : default
  end

  def integerize_input_with_default(input:, default:)
    input.present? ? input.to_i : default
  end

  def use_repository_cluster_replicas(&block)
    use_replica_clusters([ApplicationRecord::Repositories], &block)
  end

  def use_user_cluster_replicas(&block)
    if FeatureFlag.vexi.enabled?(:use_replica_for_user_lookup_2556, default: false)
      use_replica_clusters([ApplicationRecord::Mysql1], &block)
    else
      block.call
    end
  end

  def comment_variant_component
    if current_comment.copilot?
      PullRequests::Copilot::ReviewCommentComponent
    else
      PullRequests::ReviewCommentComponent
    end
  end
end
