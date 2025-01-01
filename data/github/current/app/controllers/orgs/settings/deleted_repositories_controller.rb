# typed: true
# frozen_string_literal: true

class Orgs::Settings::DeletedRepositoriesController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :dotcom_required

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    deleted_repos = Repository.owned_by(current_organization).network_safe_restoreable.order(updated_at: :desc)

    view = create_view_model(
      ::Settings::DeletedRepositoriesView,
      target: current_organization,
      deleted_repos: deleted_repos,
    )
    render "settings/organization/deleted_repositories", locals: { view: view }
  end
end
