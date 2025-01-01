# typed: true
# frozen_string_literal: true

class Businesses::SingleSignOnConfigurationController < Businesses::BusinessController
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

  before_action :single_sign_on_configuration_permission_required
  before_action :emu_business_required


  def show
    cookies.encrypted[:emu_onboarding] = true if ActiveModel::Type::Boolean.new.cast(params[:emu_onboarding])

    render "businesses/settings/identity_provider/single_sign_on_configuration"
  end

  private

  def single_sign_on_configuration_permission_required
    # Open SCIM is not supported in OIDC so we only need to check if the user can read SSO
    if this_business.oidc_enabled?
      read_enterprise_sso_required
    else
      read_enterprise_sso_or_scim_required
    end
  end
end
