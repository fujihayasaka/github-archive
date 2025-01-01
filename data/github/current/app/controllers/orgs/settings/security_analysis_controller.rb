# typed: true
# frozen_string_literal: true

class Orgs::Settings::SecurityAnalysisController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :manage_security_products_permission_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings

  javascript_bundle :"secret-scanning-bypass-reviewers-dialog"

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    repo_counts_by_public = current_organization.repositories.group(:public).count
    udp_cursor = SecretScanningCustomPatternsHelper::get_custom_patterns_cursor(params)

    render "settings/organization/security_analysis", locals: {
      public_repo_count: repo_counts_by_public&.dig(true) || 0,
      repo_count: repo_counts_by_public&.values&.sum || 0,
      cursor: udp_cursor,
      custom_patterns_query: params[:query] || "is:published,unpublished",
    }
  end
end
