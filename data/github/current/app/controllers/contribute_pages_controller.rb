# typed: true
# frozen_string_literal: true

class ContributePagesController < AbstractRepositoryController

  before_action :dotcom_required, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    if current_repository.public? && current_repository.maintained?
      render(
        "contribute_pages/show",
        locals: {
          repository: current_repository,
          issues: ExploreFeed::RepositoryGoodFirstIssue
            .fetch_by_repo_id(current_repository.id)
            .recommendable,
        },
      )
    else
      render_404
    end
  end
end
