# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::TopicsController < StafftoolsController
  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:topics]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:topics],
    optional: true

  def topics # rubocop:todo GitHub/UseRestfulActions
    repo_topics = current_repository.repository_topics.includes(:topic)

    render "stafftools/repositories/topics", locals: {
      repo_topics: repo_topics,
    }
  end
end
