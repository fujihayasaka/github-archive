# typed: true
# frozen_string_literal: true

class Orgs::Settings::ImportExport::MannequinsController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  skip_before_action :cap_pagination, only: :index

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    mannequins = if params[:query]
      current_organization.mannequins.query(params[:query])
    else
      current_organization.mannequins
    end

    render "settings/organization/import_export/mannequins",
      locals: {
        mannequins: mannequins.paginate(page: current_page, per_page: 15)
      }
  end
end
