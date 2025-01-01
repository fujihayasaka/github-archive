# rubocop:disable GitHub/UseRestfulActions
# typed: true
# frozen_string_literal: true

class PullRequests::PageData::MutationsController < AbstractRepositoryController
  extend T::Sig
  include GitHub::RateLimitedRequest
  include JsonDependency
  include VerifiedFetchDependency

  allow_verified_fetch

  before_action :login_required
  before_action :load_pull_request
  before_action :auto_merge_content_authorization_required, only: [:enable_auto_merge, :disable_auto_merge]
  before_action :update_content_authorization_required, only: [:delete_head_ref, :restore_head_ref, :mark_ready_for_review]
  skip_before_action :set_repo_as_hovercard_subject

  WRITE_RATE_LIMIT = 60

  rate_limit_requests \
    only: [:enable_auto_merge, :disable_auto_merge, :mark_ready_for_review, :delete_head_ref, :restore_head_ref],
    if: :logged_in?,
    max: WRITE_RATE_LIMIT,  # per minute
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, # 1.minute
    key: :default_rate_limit_key,
    at_limit: :render_rate_limited_response

  def auto_merge_content_authorization_required
    authorize_content(:pull_request, action_to_authorize: :auto_merge, repo: current_repository)
  end

  def update_content_authorization_required
    authorize_content(:pull_request, action_to_authorize: :update, repo: current_repository)
  end

  def enable_auto_merge
    return head 404 unless mergebox_react_partial_enabled?
    return render_404 unless current_user_can_push?

    author_email = params[:author_email].presence || current_user.git_author_email
    if current_user.is_enterprise_managed?
      return render_404 unless current_user.profile_email == author_email
      email = current_user.emails.find_by(email: current_user.email)
    else
      return render_404 unless email = current_user.emails.find_by(email: author_email)
    end

    AutoMergeRequest.enqueue!(
      pull_request: @pull_request,
      merge_method: params[:merge_method],
      user: current_user,
      email: email,
      commit_title: params[:commit_headline],
      commit_message: params[:commit_body],
      remote_ip: request.remote_ip,
    )

    render json: { message: "Auto merge request successfully created" }, status: :ok

    rescue AutoMergeRequest::Invalid => e
      render json: { message: "Failed enabling auto-merge for pull request" }, status: :unprocessable_entity
  end

  def disable_auto_merge
    return head 404 unless mergebox_react_partial_enabled?
    return render_404 unless @pull_request.can_disable_auto_merge?(actor: current_user)

    if @pull_request.auto_merge_request
      @pull_request.auto_merge_request.disable(:manually_disabled, actor: current_user)
      @pull_request.reload

      if !@pull_request.auto_merge_request
        render json: { message: "Auto merge request successfully disabled" }, status: :ok
      else
        render json: { message: "Failed disabling auto-merge for pull request" }, status: :unprocessable_entity
      end
    end
  rescue AutoMergeRequest::Invalid => e
    render  json: { message: "Failed disabling auto-merge for pull request" }, status: :unprocessable_entity
  end

  def restore_head_ref
    if @pull_request.restore_head_ref(current_user)
      render json: { message: "Head ref was successfully restored" }, status: :ok
    else
      render json: { message: "Failed to restore head ref" }, status: :unprocessable_entity
    end
  end

  def delete_head_ref
    if @pull_request.cleanup_head_ref(current_user)
      render json: { message: "Head ref was successfully deleted" }, status: :ok
    else
      render json: { message: "Could not delete head ref" }, status: :unprocessable_entity
    end
  end

  def mark_ready_for_review
    return render_404 unless @pull_request.can_change_draft_state?(current_user)

    @pull_request.ready_for_review!(user: current_user)

    render json: { message: "Pull request was successfully marked ready for review" }, status: :ok
  rescue => exception
    Failbot.report!(exception)
    render json: { message: "Pull request failed to be marked as ready for review" }, status: :internal_server_error
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
    true
  end
end
