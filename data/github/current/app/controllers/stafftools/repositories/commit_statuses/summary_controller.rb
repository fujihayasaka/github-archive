# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::CommitStatuses::SummaryController < StafftoolsController
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
    commit_sha = (params[:sha] || "").strip
    unless commit_sha.empty?
      all_commit_statuses_on_sha = Statuses.domain.list_all_for_sha(
        repository_id: current_repository.id,
        sha: commit_sha
      )

      if all_commit_statuses_on_sha.empty?
        flash[:error] = "No commit statuses found in this repository for the #{commit_sha} SHA"
        return redirect_to commit_statuses_overview_stafftools_repository_path
      else
        current_statuses_by_context = Statuses.domain.current_statuses_for_shas_group_by(repository_id: current_repository.id, shas: [commit_sha], group_by: ::Statuses::Domain::GroupByField::CONTEXT)

        return render "stafftools/repositories/commit_statuses/sha_summary", locals: { sha: commit_sha, all_commit_statuses: all_commit_statuses_on_sha, current_statuses_by_context: current_statuses_by_context }
      end
    end

    redirect_to commit_statuses_overview_stafftools_repository_path
  end
end
