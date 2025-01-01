# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::CommitStatuses::OverviewController < StafftoolsController
  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:index]

  def index
    search_parameter = (params[:search_query] || "").strip

    unless search_parameter.empty?
      if looks_like_an_oid?(search_parameter)
        # search for commit statuses using SHA
        current_by_shas = Statuses.domain.current_statuses_for_shas_group_by_sha(repository_id: current_repository.id, shas: [search_parameter])
        if current_by_shas.nil?
          flash[:error] = "No commit statuses found in this repository for the #{search_parameter} SHA"
        else
          return redirect_to commit_statuses_sha_summary_stafftools_repository_path(sha: search_parameter)
        end
      else
        # search using a single ID
        status_id = search_parameter.to_i
        commit_status = Statuses.domain.for_id(
          status_id,
          repository_id: current_repository.id
        )

        if commit_status.nil?
          flash[:error] = "No commit statuses found"
          return redirect_to commit_statuses_overview_stafftools_repository_path
        else
          # if a commit status is found, redirect to the page that shows all commit statuses for a given sha, there is no dedicated page just for a single commit SHA
          return redirect_to commit_statuses_sha_summary_stafftools_repository_path(sha: commit_status.sha)
        end
      end
    end

    render "stafftools/repositories/commit_statuses/overview"
  end

  private

  def looks_like_an_oid?(str)
    str&.match?(/\A[0-9a-f]{40}\z/)
  end
end
