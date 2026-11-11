# typed: true
# frozen_string_literal: true

require "commit_diff_entries"

class WorkspaceEditor::CommitChangesController < WorkspaceEditor::ControllerBase
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "WorkspaceEditor::CommitChangesController#create",
  ]

  before_action :parse_json_params, only: [:create]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesPushes,
    only: [:create]

  allow_verified_fetch only: [:create]

  PERMITTED_COMMIT_PARAMS = [
    :user_id,
    :author_email,
    :repository,
    :id,
    :branch,
    :branch_head,
    :message,
    :description,
    :is_quick_pull,
    diffs: [
      :old_path,
      :new_path,
      :status,
      lines: [
        :text,
        :current,
        :type,
      ]
    ]
  ]

  def create
    diff_entries = diff_params[:diffs].map do |diff|
      DiffEntryChange::DiffEntry.new(old_path: diff[:old_path], new_path: diff[:new_path], lines: diff[:lines], status: diff[:status])
    end

    author_email = diff_params[:author_email]

    change = DiffEntryChange.new(pull_request: pull, diff_entries: diff_entries)
    branch_name = diff_params[:branch]
    if diff_params[:is_quick_pull]
      branch_name = Git::Ref.normalize(branch_name) || repository.heads.temp_name(topic: "patch", prefix: current_user.display_login)
      branch_name = repository.heads.temp_name(topic: branch_name) if repository.heads.exist?(branch_name)
    end

    # fall back to the base ref and then the default branch if the pr branch has been deleted.
    current_oid = diff_params[:branch_head]
    base_ref = pull.head_ref
    if !repository.heads.exist?(pull.head_ref)
      if repository.heads.exist?(pull.base_ref)
        base_ref = pull.base_ref
      else
        base_ref = repository.default_branch
      end
      current_oid = repository.heads.find(base_ref).target_oid
    end

    begin
      result = change.commit_change_for_user(
        author: current_user,
        author_email: author_email,
        branch: branch_name || pull.head_ref,
        files: change.build_new_files,
        current_oid: current_oid,
        reflog_data: {
          real_ip: request.remote_ip,
          repo_name: repository.name_with_display_owner,
          repo_public: repository.public?,
          user_login: current_user.display_login,
          user_agent: request.user_agent,
          from: GitHub.context[:from],
          via: "GitHub editor",
        },
        message: diff_params[:message],
        description: diff_params[:description],
        is_quick_pull: diff_params[:is_quick_pull]
      )
    rescue DiffEntryChange::UnprocessableError, DiffEntryChange::InvalidAuthorEmail => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    commit_oid, _branch, _hook_error = result

    if diff_params[:is_quick_pull]
      compare_url = compare_path(repository, "#{base_ref}...#{branch_name}")
      compare_url = "#{compare_url}?quick_pull=1"
    end

    render json: { commit_oid: commit_oid, compare_url: compare_url || "" }, status: :ok
  end

  private

  memoize def pull
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
  end

  memoize def repository
    pull.head_repository
  end

  memoize def diff_params
    params.permit(PERMITTED_COMMIT_PARAMS)
  end
end
