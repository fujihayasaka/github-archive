# typed: true
# frozen_string_literal: true

class CommitCommentsController < GitContentController
  include ShowPartial
  include CommentSuggestionsHelper
  include ControllerMethods::Commit
  include Commit::ReactPayloadDataDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:minimize, :unminimize, :create, :update, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    only: [:edit_form]

  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  def create
    return unless request.post?

    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

    current_commit = current_repository.commits.find(params[:commit_id])
    attributes    = {
      user: current_user,
      repository: current_repository,
      commit_id: params[:commit_id],
      path: params[:path],
      position: params[:position],
      line: params[:line],
      body: params[:comment].nil? ? nil : params[:comment][:body],
    }

    comment = CommitComment.new(attributes)
    if comment.save
      async_mark_thread_as_read current_commit

      GitHub.instrument "comment.create", user: current_user

      if comment.inline?
        respond_to do |format|
          format.json do
            render json: {
              comment: build_commit_comment_payload(comment, current_user, current_repository, cap_filter)
            }
          end
        end
      else
        respond_to do |format|
          format.json do
            if react_commit_enabled?
              render json: {
                comment: build_commit_comment_payload(comment, current_user, current_repository, cap_filter)
              }
            else
              comments = CommitComment.for_display(current_user, current_commit, current_repository)
              current_commit.comments = [comment]
              current_commit.comment_count = comments.discussion.count
              render_update_content_json({
                timeline_marker: render_to_string(
                  partial: "commit/timeline_marker",
                  object: current_commit,
                  formats: :html,
                ),
                visible_comments_header: render_to_string(
                  partial: "commit/visible_comments_header",
                  object: current_commit,
                  formats: :html,
                ),
              })
            end
          end
        end
      end
    else
      head :unprocessable_entity
    end
  end

  def update
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

    comment = current_comment
    if can_modify_commit_comment?(comment)
      # prevent updates from stale data
      if stale_model?(comment)
        return render_stale_error(model: comment, error: "Could not edit comment. Please try again.", path: redirect_path(comment))
      end

      if operation = TaskListOperation.from(params[:task_list_operation])
        text = operation.call(comment.body)
        comment.update_body(text, current_user) if text
      else
        comment.update_body(params[:commit_comment][:body], current_user)
      end

      respond_to do |format|
        format.json do
          if comment.valid?
            render json: {
              "source" => comment.body,
              "body" => comment.body_html,
              "newBodyVersion" => comment.body_version,
              "editUrl" => show_comment_edit_history_path(comment.global_relay_id),
            }
          else
            render json: comment.errors, status: :unprocessable_entity
          end
        end

        format.html do
          unless comment.valid?
            flash[:error] = "Could not edit comment."
          end

          redirect_to redirect_path(comment)
        end
      end
    else
      access_denied
    end
  end

  def destroy
    comment = current_comment

    if site_admin? || (logged_in? && (
        comment.user_id == current_user.id ||
        comment.repository.pushable_by?(current_user)))
      comment.destroy
      respond_to do |format|
        format.html do
          redirect_to redirect_path(comment, false)
        end
        format.json do
          head 200
        end
      end
    else
      access_denied
    end
  end

  # TODO : remove this method as we no longer need to support the old comment UI
  def show
    render Comments::CommitCommentComponent.new(commit_comment: current_comment, repository: current_repository, render_minimized: true), formats: [:html], layout: false
  end

  def minimize # rubocop:todo GitHub/UseRestfulActions
    unless current_comment.async_minimizable_by?(current_user).sync
      return head :unprocessable_entity
    end

    comment_author = current_comment.user || User.ghost
    if current_comment.set_minimized(current_user, nil, params[:classifier], comment_author)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def unminimize # rubocop:todo GitHub/UseRestfulActions
    unless current_comment.async_unminimizable_by?(current_user).sync
      return head :unprocessable_entity
    end

    comment_author = current_comment.user || User.ghost
    if current_comment.set_unminimized(current_user, nil, params[:classifier], comment_author)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def comment_actions_menu # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    render partial: "comments/review_comment_actions", locals: {
      tab: nil,
      comment: current_comment,
      can_open_new_issue: false,
      form_path: commit_comment_path(current_repository.owner, current_repository, current_comment),
    }
  end

  def edit_form # rubocop:todo GitHub/UseRestfulActions
    if can_modify_commit_comment?(current_comment)
      render Comments::EditForm::EditFormComponent.new(
        comment: current_comment,
        comment_context: params[:comment_context],
        textarea_id: params[:textarea_id]
      ), layout: false
    else
      head :forbidden
      nil
    end
  end

  private

  def authorized?
    params[:action] == "create" ? (logged_in? && super) : super
  end

  memoize def current_comment
    if react_commit_enabled? && params[:commit_comment].present? && params[:commit_comment][:id].present?
      current_repository.commit_comments.find(params[:commit_comment][:id])
    else
      current_repository.commit_comments.find(params[:id])
    end
  end

  def redirect_path(comment, deep_link = true)
    if params[:pull_request_number]
      "#{pull_request_path(params[:pull_request_number].to_i, comment.commit.repository)}#{deep_link ? "#discussion_r#{comment.id}" : ""}"
    else
      commit_path(comment.commit)
    end
  end

  def route_supports_advisory_workspaces?
    true
  end
end
