# typed: true
# frozen_string_literal: true

class Repos::Dependabot::AutofixController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::PartialRenderWithLayoutDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Repos::Dependabot::AutofixController#create",
  ]

  before_action :login_required
  before_action :writable_repository_required, only: [:create]
  before_action :content_authorization_required, only: [:create]
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
    ApplicationRecord::IamAbilities, only: [:create, :review_comment_partial]

  depends_on_clusters \
    ApplicationRecord::SecurityOverviewAnalytics,
    optional: true,
    only: [:create]

  def create
    pull = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)

    autofix_job_id = params[:autofix_job_id]&.to_i

    unless autofix_job_id
      return render json: { error: "No suggested fix available" }, status: :unprocessable_entity
    end

    response = Dependabot::Twirp.suggested_fixes_client.get_suggested_fix(
      autofix_job_id: autofix_job_id,
      github_pull_request_number: pull.number,
      github_repo_id: current_repository.id,
    )
    suggested_fix = response.suggested_fix

    return render json: { error: "No suggested fix available" }, status: :unprocessable_entity if suggested_fix.nil?

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
        co_author_note: dependabot_co_author_note,
        reflog_data: {
          real_ip: request.remote_ip,
          repo_name: suggested_change.repository.name_with_display_owner,
          repo_public: suggested_change.repository.public?,
          user_login: current_user.display_login,
          user_agent: request.user_agent,
          from: GitHub.context[:from],
          via: "dependabot suggested fix",
        }
      )
    rescue DiffEntrySuggestedChange::NotFoundError => e
      return render json: { error: e.message }, status: :not_found
    rescue DiffEntrySuggestedChange::ForbiddenError => e
      return render json: { error: e.message }, status: :forbidden
    rescue DiffEntrySuggestedChange::UnprocessableError => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    review_thread = pull.review_threads.find(params[:pull_request_review_thread_id])
    review_thread.resolve(resolver: dependabot_bot) if review_thread

    Dependabot::Twirp.suggested_fixes_client.apply_suggested_fix(
      autofix_job_id: autofix_job_id,
      github_pull_request_number: pull.number,
      github_repo_id: current_repository.id,
    )

    GlobalInstrumenter.instrument("dependabot.autofix_event", {
      repository_id: current_repository.id,
      autofix_job_id: autofix_job_id,
      event_type: :AUTOFIX_EVENT_TYPE_COMMITTED,
      pull_request_id: pull.id,
      pull_request_number: pull.number,
    })

    flash[:notice] = "Suggested fix successfully applied"
    head :ok
  end

  def review_comment_partial # rubocop:todo GitHub/UseRestfulActions
    pull = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)

    pr_review_comment = PullRequestReviewComment.find_by(
      repository: current_repository,
      pull_request: pull,
      id: params[:comment_id]
    )

    return head(:not_found) if pr_review_comment.nil?

    respond_to do |format|
      format.html do
        render Dependabot::ReviewCommentComponent.new(pull_request_review_comment: pr_review_comment, pull_request: pull), layout: component_fragment_layout
      end
    end
  end

  private

  def dependabot_co_author_note
    "Co-authored-by: Copilot Autofix powered by AI <#{dependabot_bot.git_author_email}>"
  end

  def content_authorization_required
    authorize_content(:pull_request, repo: current_repository, action_to_authorize: :apply_suggestions)
  end

  memoize def dependabot_bot
    Apps::Privileged.integration(:dependabot).bot or fail "dependabot integration not installed!"
  end
end
