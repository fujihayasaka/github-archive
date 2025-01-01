# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AutofixController < AbstractRepositoryController
  include CodeScanningHelper
  include ScanningControllerMethods
  include ApplicationController::JsonDependency
  include ApplicationController::PartialRenderWithLayoutDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Repos::CodeScanning::AutofixController#apply_suggested_fix",
  ]

  before_action :login_required
  before_action :check_code_scanning_read, only: :generate_autofix
  before_action :check_code_scanning_write, only: :open_workspace_editor
  before_action :writable_repository_required, only: [:apply_suggested_fix, :review_comment_partial, :open_workspace_editor]
  before_action :content_authorization_required, only: [:apply_suggested_fix, :open_workspace_editor]
  skip_before_action :cap_pagination

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities, only: [:open_workspace_editor, :apply_suggested_fix, :review_comment_partial]

  depends_on_clusters \
    ApplicationRecord::SecurityOverviewAnalytics,
    optional: true,
    only: [:apply_suggested_fix, :review_comment_partial]

  preload_features [
    :disable_code_scanning,
  ]

  def apply_suggested_fix # rubocop:todo GitHub/UseRestfulActions
    pull = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)
    alert_number = params[:alert_number].to_i

    review_comment = begin
      PullRequestReviewComment.where(repository: current_repository, pull_request: pull).find(params[:comment_id])
    rescue ActiveRecord::RecordNotFound => e
      return render json: { error: "Could not find comment" }, status: :not_found
    end

    csrc = CodeScanningReviewComment.find_by(repository: T.must(review_comment.repository).id, pull_request: T.must(review_comment.pull_request).id, pull_request_review_comment: review_comment.id)
    return render json: { error: "Comment must match the alert being fixed" }, status: :unprocessable_entity unless csrc&.alert_number == alert_number

    ref_names_bytes = pull.build_ref_names_bytes_for_code_scanning_suggested_fix
    if params[:current_oid].blank?
      return render json: { error: "No suggested fix available" }, status: :unprocessable_entity
    end

    begin
      suggested_fix = CodeScanning::AutofixSuggestion.fetch_applicable_suggested_fix_alerts(
        repository: current_repository,
        alert_numbers: [alert_number],
        head_commit_oid: params[:current_oid],
        ref_names_bytes:
      )[alert_number]&.suggested_fix
    rescue CodeScanning::AutofixError => e
      return render json: { error: e.message }, status: e.status
    end

    suggested_change = DiffEntrySuggestedChange.new(
      repository: pull.head_repository,
      pull_request: pull,
      diff_entries: CodeScanning::AutofixSuggestion.new(suggested_fix).diff_entries
    )
    begin
      suggested_change.commit_change_for_user(
        author: current_user,
        current_oid: params[:current_oid],
        message: params[:message].to_s,
        sign: true,
        co_author_note: code_scanning_bot_co_author_note,
        reflog_data: {
          real_ip: request.remote_ip,
          repo_name: suggested_change.repository.name_with_display_owner,
          repo_public: suggested_change.repository.public?,
          user_login: current_user.display_login,
          user_agent: request.user_agent,
          from: GitHub.context[:from],
          via: "code scanning suggested fix",
        }
      )
    rescue DiffEntrySuggestedChange::NotFoundError => e
      return render json: { error: e.message }, status: :not_found
    rescue DiffEntrySuggestedChange::ForbiddenError => e
      return render json: { error: e.message }, status: :forbidden
    rescue DiffEntrySuggestedChange::UnprocessableError => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    response = GitHub::Turboscan::SuggestedFixes.apply_suggested_fix(
      repository_id: current_repository.id,
      alert_number: alert_number,
      ref_names_bytes: ref_names_bytes,
      actor_id: current_user.id,
    )

    GlobalInstrumenter.instrument("code_scanning.autofix_event", {
      repository_id: current_repository.id,
      alert_number: alert_number,
      event_type: :AUTOFIX_EVENT_TYPE_COMMITTED,
      pull_request_id: pull.id,
      pull_request_number: pull.number,
    })

    flash[:notice] = "Alert fix successfully applied."
    head :ok
  end

  def feedback # rubocop:todo GitHub/UseRestfulActions
    pull_request = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)

    payload = {
      repository_id: current_repository.id,
      alert_number: params[:alert_number].to_i,
      user_analytics_tracking_id: current_user.analytics_tracking_id,
      pull_request_id: pull_request.id,
      pull_request_number: pull_request.number,
      type: params[:feedback],
    }

    if params[:feedback_choice].present?
      # validate feedback choices
      params[:feedback_choice].each do |choice|
        unless CodeScanning::Autofix::FEEDBACK_OPTIONS.include?(choice.to_sym)
          head :bad_request
          return
        end
      end
      payload.merge!(choice: params[:feedback_choice])
    end

    if params[:text_response].present?
      unless params[:text_response].is_a?(String)
        head :bad_request
        return
      end
      payload.merge!(text_response: params[:text_response])
    end

    GlobalInstrumenter.instrument("code_scanning.autofix_feedback", payload)

    head :ok
  end

  def review_comment_partial # rubocop:todo GitHub/UseRestfulActions
    pull = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)

    # For consistency there is an alert number param but it's not currently used.
    # alert_number = params[:alert_number].to_i

    pr_review_comment = PullRequestReviewComment.find_by(
      repository: current_repository,
      pull_request: pull,
      id: params[:comment_id]
    )

    return head(:not_found) if pr_review_comment.nil?

    CodeScanning::ReviewCommentComponent.preload_review_comment(pull_request: pull, pull_request_review_comment: pr_review_comment)

    respond_to do |format|
      format.html do
        render CodeScanning::ReviewCommentComponent.new(pull_request_review_comment: pr_review_comment, pull_request: pull), layout: component_fragment_layout
      end
    end
  end

  def generate_autofix # rubocop:todo GitHub/UseRestfulActions
    alert_numbers = Array(params[:number]).map(&:to_i).uniq
    return head :bad_request if alert_numbers.empty?

    default_ref = current_repository.default_branch_ref
    render_404 and return unless default_ref

    response = CodeScanning::AutofixSuggestion.generate(
      repository: current_repository,
      alert_numbers:,
      ref_names_bytes: Array(default_ref.qualified_name.b),
      source: :SUGGESTED_FIX_SOURCE_ONDEMAND
    )

    if response.blank? || response.error.present?
      flash[:error] = "There was an issue creating the autofix suggestion. Please try again."
    end

    redirect_back fallback_location: repository_code_scanning_result_path(current_repository.owner, current_repository, number: params[:number])
  end

  def open_workspace_editor # rubocop:todo GitHub/UseRestfulActions
    pr_review_comment = PullRequestReviewComment.includes(:pull_request).find_by(id: params[:pull_request_review_comment_id], repository: current_repository)
    alert_number = params[:number].to_i
    path = params[:path]
    return render_404 unless pr_review_comment && alert_number > 0

    pr = pr_review_comment.pull_request
    render_404 and return unless pr

    # Track when the open editor button is clicked
    GlobalInstrumenter.instrument("code_scanning.autofix_event", {
      repository_id: current_repository.id,
      alert_number:,
      event_type: :AUTOFIX_EVENT_TYPE_WORKSPACE_EDITOR_OPENED,
      pull_request_id: pr&.id,
      pull_request_number: pr&.number,
    })

    # Redirect to the workspace editor
    redirect_to repo_workspace_editor_edit_path(
      id: pr&.number,
      user_id: current_repository.owner_display_login,
      repository: current_repository,
      path:,
      pull_request_review_comment_id: pr_review_comment.id
    )
  end

  private

  def code_scanning_bot_co_author_note
    code_scanning_app = Apps::Privileged.integration(:code_scanning)
    raise "code scanning integration not installed!" if code_scanning_app.nil?

    "Co-authored-by: Copilot Autofix powered by AI <#{code_scanning_app.bot.git_author_email}>"
  end

  def content_authorization_required
    authorize_content(:pull_request, repo: current_repository, action_to_authorize: :apply_suggestions)
  end
end
