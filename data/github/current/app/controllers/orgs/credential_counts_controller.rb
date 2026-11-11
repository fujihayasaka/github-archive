# typed: true
# frozen_string_literal: true

class Orgs::CredentialCountsController < Orgs::Controller
  before_action :ensure_not_github_enterprise
  before_action :ensure_organization_credentials_ui_enabled
  before_action :ensure_sso_enabled
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Permissions,
    only: [:show]

  def show
    respond_to do |format|
      format.html do
        counts = this_organization.fetch_credential_counts
        render partial: "orgs/security_settings/credential_counts", locals: {
          counts: counts,
          timed_out: counts[:timed_out]
        }
      end
    end
  end

  private

  def ensure_not_github_enterprise
    render_404 if GitHub.enterprise?
  end

  def ensure_organization_credentials_ui_enabled
    unless this_organization.feature_flag_enabled?(:organization_credentials_ui, default: false)
      render_404
    end
  end

  def ensure_sso_enabled
    render_404 if !this_organization.sso_enabled_on_business? && !this_organization.saml_sso_enabled?
  end
end
