# typed: true
# frozen_string_literal: true

class Orgs::Settings::SecurityAnalysis::GhasHeaderController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :manage_security_products_permission_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  skip_before_action :cap_pagination

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    return render_404 unless current_organization.advanced_security_purchased?
    render Organizations::Settings::GhasRepositoriesHeaderComponent.new(sku: GitHub::Turboghas::SKU.from_param(params[:sku]), organization: current_organization), layout: false
  end
end
