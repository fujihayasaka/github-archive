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

  before_action :business_owner_required
  before_action :emu_business_required


  def show
    return render_404 unless this_business.feature_enabled?(:move_emu_sso_configuration_page)
    cookies.encrypted[:emu_onboarding] = true if ActiveModel::Type::Boolean.new.cast(params[:emu_onboarding])

    render "businesses/settings/identity_provider/single_sign_on_configuration"
  end
end
