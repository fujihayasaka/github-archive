# typed: true
# frozen_string_literal: true

class Businesses::SamlToOIDCMigrationController < Businesses::BusinessController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  before_action :emu_business_required
  before_action :first_emu_owner_required
  before_action :saml_sso_required

  def show
    render "businesses/settings/identity_provider/saml_to_oidc_migration"
  end

  private

  def first_emu_owner_required
    render_404 unless this_business.is_first_emu_owner?(user: current_user)
  end

  def saml_sso_required
    render_404 unless this_business.saml_sso_enabled?
  end
end
