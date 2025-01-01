# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AutofixController < AbstractRepositoryController
  include CodeScanningHelper
  include ApplicationController::JsonDependency
  include ApplicationController::PartialRenderWithLayoutDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Repos::CodeScanning::AutofixController#apply_suggested_fix",
  ]

  before_action :login_required
  before_action :writable_repository_required
  before_action :content_authorization_required, only: [:apply_suggested_fix]
  before_action :autofix_must_be_enabled
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
    ApplicationRecord::Commits,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities, only: [:apply_suggested_fix, :review_comment_partial]

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

    response = GitHub::Turboscan::SuggestedFixes.suggested_fix(
      repository_id: current_repository.id,
      alert_numbers: [alert_number],
      head_commit_oid: params[:current_oid],
      ref_names_bytes:,
    )

    return render json: { error: "Something went wrong" }, status: :internal_server_error if response&.error.present?

    suggested_fix = response&.data&.suggested_fix_alerts&.[](alert_number)&.suggested_fix

    return render json: { error: "No suggested fix available" }, status: :unprocessable_entity if suggested_fix.nil? || suggested_fix.outdated
    return render json: { error: "Can't apply a suggested fix that has been dismissed" }, status: :unprocessable_entity if suggested_fix.dismissed

    diff_entries = suggested_fix.files.each_with_object([]) do |file, out|
      parser = GitHub::Diff::Parser.new(file.diff_content)
      parser.each do |entry|
        out << entry
      end
    end

    suggested_change = DiffEntrySuggestedChange.new(repository: pull.head_repository, pull_request: pull, diff_entries:)
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
    pull = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)
    alert_number = params[:alert_number].to_i

    # These lookups are technically not needed but they act as sanity checks of the relations between the PR, review comment and alert.
    pr_review_comment = PullRequestReviewComment.find_by(
      repository: current_repository,
      pull_request: pull,
      id: params[:comment_id]
    )
    cs_review_comment = CodeScanningReviewComment.find_by(
      repository: current_repository,
      pull_request: pull,
      pull_request_review_comment: pr_review_comment,
      alert_number:,
    )

    if params[:current_oid].blank? || cs_review_comment.nil?
      return redirect_to(gh_show_pull_request_path(pull))
    end

    if params[:thumbs] == "down"
      unless pull.can_dismiss_code_scanning_suggested_fix?(current_user)
        flash[:error] = "You are not allowed to provide feedback for this suggested fix."
        return redirect_to(gh_show_pull_request_path(pull))
      end

      ref_names_bytes = pull.build_ref_names_bytes_for_code_scanning_suggested_fix

      response = GitHub::Turboscan::SuggestedFixes.dismiss_suggested_fix(
        repository_id: current_repository.id,
        alert_number:,
        ref_names_bytes:,
        actor_id: current_user.id,
        reason: params[:reason].is_a?(String) ? params[:reason].slice(0, 280) : "",
      )

      if response&.data&.success
        flash[:notice] = "Alert fix has been dismissed."
        GlobalInstrumenter.instrument("code_scanning.autofix_event", {
          repository_id: current_repository.id,
          alert_number: alert_number,
          event_type: :AUTOFIX_EVENT_TYPE_DISMISSED,
          pull_request_id: pull.id,
          pull_request_number: pull.number,
        })
      end

      if response&.error.present?
        flash[:error] = "Something went wrong"
      end
    end

    redirect_to(gh_show_pull_request_path(pull))
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

    CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: pull)

    respond_to do |format|
      format.html do
        render CodeScanning::ReviewCommentComponent.new(pull_request_review_comment: pr_review_comment, pull_request: pull), layout: component_fragment_layout
      end
    end
  end

  def create_autofix_pr # rubocop:todo GitHub/UseRestfulActions
    alert_number = params[:number].to_i
    begin
      # NOTE: This is opening a PR on the behalf of the user. Should this be on behalf of the github-advinced-security bot?
      pull_request = CodeScanning::Autofix.generate_pr_for_alert(current_repository, current_user, alert_number)

      GitHub::Turboscan.create_alert_links(
        repository_id: current_repository.id,
        alert_numbers: [alert_number],
        pull_request_id: pull_request.id,
      )
    rescue CodeScanning::AutofixError, DiffEntrySuggestedChange::UnprocessableError, DiffEntrySuggestedChange::NotFoundError => e
      flash[:error] = e.message
      redirect_to :back
      return
    end
    redirect_to(gh_show_pull_request_path(pull_request))
  end

  private

  def autofix_must_be_enabled
    return if CodeScanning::Autofix.enabled_for_repo?(current_repository)

    render json: { error: "autofix needs to be enabled" }, status: :forbidden
  end

  def code_scanning_bot_co_author_note
    code_scanning_app = Apps::Internal.integration(:code_scanning)
    raise "code scanning integration not installed!" if code_scanning_app.nil?

    "Co-authored-by: Copilot Autofix powered by AI <#{code_scanning_app.bot.git_author_email}>"
  end

  def content_authorization_required
    authorize_content(:pull_request, repo: current_repository, action_to_authorize: :apply_suggestions)
  end
end
