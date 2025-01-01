# typed: true
# frozen_string_literal: true

class PullRequestReviewThreadResolutionsController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true, only: [:show]

  MORE_COMMENTS_LIMIT = 20

  before_action :find_review_thread, only: [:create, :destroy]

  def create
    if @review_thread.nil?
      render status: 404, json: { errors: "Review thread not found" }
      return
    end

    unless @review_thread.async_can_resolve(current_user).sync
      if @review_thread.conversation?
        render status: 401, json: { errors: "User is not authorized to resolve the conversation" }
      else
        render status: 422, json: { errors: "The thread is not a conversation and cannot be resolved" }
      end
      return
    end

    begin
      @review_thread.resolve(resolver: current_user)
    rescue PullRequestReviewThread::ResolveReviewThreadError => e
      render status: 422, json: { errors: e.message }
      return
    end

    if @review_thread.errors.any?
      render status: 422, json: { errors: @review_thread.errors.full_messages.to_sentence }
    else
      render_thread_partial(@review_thread)
    end
  end

  def destroy
    if @review_thread.nil?
      render status: 404, json: { errors: "Review thread not found" }
      return
    end

    unless @review_thread.async_can_unresolve(current_user).sync
      render status: 401, json: { errors: ["User is not allowed to unresolve the conversation"] }
      return
    end

    @review_thread.unresolve(unresolver: current_user)

    if @review_thread.errors.any?
      render status: 422, json: { errors: @review_thread.errors.full_messages.to_sentence }
    else
      render_thread_partial(@review_thread)
    end
  end

  def more_comments # rubocop:todo GitHub/UseRestfulActions
    pull_request = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)
    return render_404 unless pull_request

    pull_request_review_thread = pull_request.review_threads.find(params[:thread_id])
    return render_404 unless pull_request_review_thread

    after = (params[:after] || 0).to_i
    before = (params[:before] || 0).to_i

    page_info = pull_request_review_thread.prelude_paginated_review_comments_for(current_user, { first: MORE_COMMENTS_LIMIT, after: after, before: before })
    page_info[:before] = before

    preload_code_scanning_alerts(pull_request_review_thread)
    render PullRequests::ReviewThreadPagedCommentsComponent.new(pull_request_review_thread: pull_request_review_thread, page_info: page_info, pull_request: pull_request), layout: false
  end

  def show
    pull_request = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)
    return render_404 unless pull_request

    pull_request_review_thread = pull_request.review_threads.find(params[:thread_id])
    return render_404 unless pull_request_review_thread

    preload_code_scanning_alerts(pull_request_review_thread)
    render PullRequests::ReviewThreadBodyComponent.new(
      review_thread_or_comment: pull_request_review_thread,
      pull_request: pull_request,
      rendering_on_files_tab: rendering_on_files_tab,
      highlighting_mode: Diffs::DeferredDiffLinesComponent::HighlightingModes::IMMEDIATE
    ), layout: false
  end

  private

  def rendering_on_files_tab
    params[:rendering_on_files_tab] == "true"
  end

  def render_thread_partial(review_thread)
    preload_code_scanning_alerts(review_thread)

    render PullRequests::ReviewThreadComponent.new(
      review_thread_or_comment: review_thread,
      pull_request: review_thread.pull_request,
      rendering_on_files_tab: rendering_on_files_tab,
    ), layout: false
  end

  def route_supports_advisory_workspaces?
    true
  end

  def find_review_thread
    @review_thread = PullRequestReviewThread.includes(:pull_request).find_by(id: params[:thread_id])
  end

  def preload_code_scanning_alerts(review_thread)
    pull = review_thread.pull_request
    return if "code_scanning" != review_thread.pull_request_review&.variant_type
    CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: pull)
  end
end
