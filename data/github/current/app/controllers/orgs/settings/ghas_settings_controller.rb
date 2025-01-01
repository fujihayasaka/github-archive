# typed: true
# frozen_string_literal: true

class Orgs::Settings::GhasSettingsController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :manage_security_products_permission_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    ApplicationRecord::SecurityOverviewAnalytics,
    optional: true,
    only: [:index]

  def index
    repo_counts_by_public = current_organization.repositories.group(:public).count
    pattern_configs_enabled_count, _err = ::SecretScanning::Services::PatternConfigsService.get_enabled_patterns_count(org, current_user)

    respond_to do |format|
      format.html do
        render Settings::SecurityAnalysisGhasSettingsComponent.new(
          owner: current_organization,
          public_repo_count: repo_counts_by_public&.dig(true) || 0,
          repo_count: repo_counts_by_public&.values&.sum || 0,
          cursor: params[:cursor],
          custom_patterns_query: params[:custom_patterns_query],
          pattern_configs_enabled_count:,
        ), layout: false
      end
    end
  end

  private

  sig { returns(Organization) }
  def org
    current_organization
  end
end
