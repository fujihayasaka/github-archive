# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/RailsControllerRenderLiteral

class PullRequestReviewsController < AbstractRepositoryController
  include CommentsHelper
  include ApplicationController::PartialRenderWithLayoutDependency

  before_action :login_required
  before_action :load_current_pull_request

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    only: [:edit_form]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:more_threads, :show]

  depends_on_clusters ApplicationRecord::Mysql5,
    optional: true, only: [:more_threads]

  depends_on_clusters ApplicationRecord::Spokes,
    optional: true, only: [:edit_form]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true, only: [:edit_form, :more_threads, :show]

  def update
    review = @pull.reviews.find(params[:review_id])

    content =
      if operation = TaskListOperation.from(params[:task_list_operation])
        operation.call(params[:pull_request_review][:body])
      else
        params[:pull_request_review][:body]
      end

    if review && review.editable_by?(current_user)
      # prevent updates from stale data
      if stale_model?(review)
        return render_stale_error(model: review, error: "Could not edit review. Please try again.", path: pull_request_path(@pull, @pull.repository))
      end

      async_mark_thread_as_read(review)
      review.update_body(content, current_user)
    end

    respond_to do |format|
      format.json do
        if review.valid?
          render json: {
            "source" => review.body,
            "body" => review.body_html(context: { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }),
            "newBodyVersion" => review.body_version,
            "editUrl" => show_comment_edit_history_path(review.global_relay_id),
          }
        else
          render json: { errors: review.errors.full_messages }, status: :unprocessable_entity
        end
      end
      format.html do
        unless review.valid?
          flash[:error] = "Could not edit review."
        end

        redirect_to pull_request_path(@pull, @pull.repository)
      end
    end
  end

  def edit_form # rubocop:todo GitHub/UseRestfulActions
    review = @pull.reviews.find(params[:review_id])
    unless review.editable_by?(current_user)
      head :forbidden
      return
    end

    render Comments::EditForm::EditFormComponent.new(
      comment: review,
      comment_context: params[:comment_context],
      textarea_id: params[:textarea_id],
      slash_commands_enabled: current_user.slash_commands_enabled?,
      slash_commands_surface: SlashCommands::PULL_REQUEST_SURFACE,
      current_repository: @pull.repository
    ), layout: false, formats: [:html]
  end

  MORE_THREADS_LIMIT = 20

  def more_threads # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull

    pull_request_review = @pull.reviews.find(params[:review_id])
    return render_404 unless pull_request_review

    after = (params[:after] || 0).to_i
    before = (params[:before] || 0).to_i

    page_info = pull_request_review.prelude_paginated_review_threads_and_replies_for(current_user, { first: MORE_THREADS_LIMIT, after: after, before: before })
    page_info[:before] = before

    # We need to preload code scanning review comments here even if this pull_request_review is not from
    # code scanning in case some of its comments are replies to a code scanning review comment. In such case,
    # we will need to check if the code scanning review comment correpsonds to a fixed or dismissed alert
    # so we know whether to make the comment collapsed by default.
    CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: @pull)

    render PullRequests::ReviewPagedThreadsComponent.new(pull_request_review: pull_request_review, page_info: page_info, pull_request: @pull), layout: component_fragment_layout
  end

  def show
    review = @pull.reviews.find(params[:review_id])

    # We need to preload code scanning review comments here even if this pull_request_review is not from
    # code scanning in case some of its comments are replies to a code scanning review comment. In such case,
    # we will need to check if the code scanning review comment correpsonds to a fixed or dismissed alert
    # so we know whether to make the comment collapsed by default.
    CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: @pull)

    render PullRequests::ReviewComponent.new(pull_request_review: review, pull_request: @pull, render_if_minimized: true), formats: [:html], layout: false
  end

  def minimize # rubocop:todo GitHub/UseRestfulActions
    review = @pull.reviews.find(params[:review_id])
    unless review && review.async_minimizable_by?(current_user).sync
      return head :unprocessable_entity
    end

    review_author = review.user || User.ghost
    if review.set_minimized(current_user, nil, minimize_classifier, review_author)
      render PullRequests::ReviewComponent.new(pull_request_review: review, pull_request: @pull, render_if_minimized: false), formats: [:html], layout: false
    else
      head :unprocessable_entity
    end
  end

  def unminimize # rubocop:todo GitHub/UseRestfulActions
    review = @pull.reviews.find(params[:review_id])

    unless review && review.async_unminimizable_by?(current_user).sync
      return head :unprocessable_entity
    end

    review_author = review.user || User.ghost
    if review.set_unminimized(current_user, nil, nil, review_author)
      render PullRequests::ReviewComponent.new(pull_request_review: review, pull_request: @pull, render_if_minimized: false), formats: [:html], layout: false
    else
      head :unprocessable_entity
    end
  end

  private

  def minimize_classifier
    T.must(Platform::Enums::ReportedContentClassifiers.values[params[:classifier]]).value
  end

  def load_current_pull_request
    @pull = current_repository.issues.find_by_number(params[:pull_id].to_i).try(:pull_request)
    return render_404 unless @pull
  end

  def route_supports_advisory_workspaces?
    %w[edit_form update].include?(action_name)
  end
end
