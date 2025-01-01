# typed: true
# frozen_string_literal: true

class Businesses::ProfilesController < Businesses::BusinessController
  before_action :business_owner_required

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:show]
  before_action :enable_microsoft_analytics, only: [:show]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:show]
  layout "enterprise_funnel", only: [:show]

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    render "businesses/settings/profile"
  end

  def update
    if this_business.update(profile_params)
      redirect_to settings_profile_enterprise_path(this_business),
        notice: "Got it. The profile has been updated."
    else
      flash.now[:error] = this_business.errors.full_messages.join(", ")
      render "businesses/settings/profile"
    end
  end

  private

  memoize def profile_params
    params.require(:business).permit(:name, :description, :website_url, :location)
  end
end
