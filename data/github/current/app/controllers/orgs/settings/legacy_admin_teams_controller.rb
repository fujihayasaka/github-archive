# typed: true
# frozen_string_literal: true

class Orgs::Settings::LegacyAdminTeamsController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    @legacy_admin_teams   = current_organization.teams.legacy_admin
    return render_404 if @legacy_admin_teams.none?

    @legacy_admin_members = current_organization.legacy_admin_members

    render "settings/organization/teams"
  end
end
