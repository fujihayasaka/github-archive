# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::SecurityProductsController < StafftoolsController
  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/overview"

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::SecurityOverviewAnalytics,
    ApplicationRecord::Spokes

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true

  def show
    repository_security_configuration = RepositorySecurityConfiguration.find_by(repository_id: current_repository.id)
    security_configuration = repository_security_configuration&.security_configuration

    render "stafftools/repositories/security_products", locals: {
      repository_security_configuration:,
      security_configuration:,
      owner: current_repository.owner,
    }
  end
end
