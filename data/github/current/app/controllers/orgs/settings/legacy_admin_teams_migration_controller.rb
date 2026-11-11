# typed: true
# frozen_string_literal: true

class Orgs::Settings::LegacyAdminTeamsMigrationController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def create
    current_organization.migrate_legacy_admin_teams
    flash[:notice] = "Migrating all of your organization's legacy admin teams. This could take a couple minutes."

    redirect_to settings_org_teams_path(current_organization)
  end
end
