# typed: true
# frozen_string_literal: true

require "commit_diff_entries"

class Copilot::TaskCommitChangesController < Copilot::TaskControllerBase
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Copilot::TaskCommitChangesController#create",
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

    begin
      result = change.commit_change_for_user(
        author: current_user,
        author_email: author_email,
        files: change.build_new_files,
        current_oid: diff_params[:branch_head],
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
        description: diff_params[:description]
      )
    rescue DiffEntryChange::UnprocessableError, DiffEntryChange::InvalidAuthorEmail => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    commit_oid, _branch, _hook_error = result

    render json: { commit_oid: commit_oid }, status: :ok
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
