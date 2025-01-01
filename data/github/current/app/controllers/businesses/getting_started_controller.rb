# typed: true
# frozen_string_literal: true

class Businesses::GettingStartedController < Businesses::BusinessController
  include BusinessesHelper

  before_action :dotcom_required
  before_action :login_required
  before_action :business_basic_access_or_owner_required
  before_action :ensure_user_can_view_onboarding

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  layout "enterprise_funnel"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(show)

  def show
    render "businesses/getting_started"
  end

  private

  def ensure_user_can_view_onboarding
    return if show_onboarding_experience?(this_business)
    return if show_org_upgrade_onboarding_experience?(this_business)

    redirect_to enterprise_path(this_business)
  end
end
