# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::CredentialCountsController < StafftoolsController
  before_action :dotcom_required
  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :ensure_organization_credentials_ui_enabled
  before_action :ensure_sso_enabled

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    respond_to do |format|
      format.html do
        counts = this_user.fetch_credential_counts
        render partial: "stafftools/organizations/credential_counts", locals: {
          organization: this_user,
          counts: counts,
          timed_out: counts[:timed_out]
        }
      end
    end
  end

  private

  def ensure_organization_credentials_ui_enabled
    render_404 unless this_user.feature_flag_enabled?(:organization_credentials_ui, default: false)
  end

  def ensure_sso_enabled
    render_404 if !this_user.sso_enabled_on_business? && !this_user.saml_sso_enabled?
  end
end
