# typed: strict
# frozen_string_literal: true

class OrganizationOnboarding::AdvancedSecurityController < OrganizationOnboarding::ApplicationController
  extend T::Sig

  before_action :ensure_billing_enabled
  before_action :has_active_or_recent_trial_required

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:show]
  before_action :enable_microsoft_analytics, only: [:show]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:show]
  layout "enterprise_funnel", only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    only: [:show]

  stylesheet_bundle :advanced_security_organization_onboarding
  stylesheet_bundle :settings

  sig { void }
  def show
    return render_404 if GitHub.multi_tenant_enterprise?

    business = current_organization.business
    advanced_security_subscription_item = business&.advanced_security_subscription_item
    render "settings/organization/advanced_security/show", locals:
      {
        trial_active: business&.has_active_advanced_security_trial?,
        business: business,
        advanced_security_subscription_item: advanced_security_subscription_item,
      }
  end

  private

  sig { void }
  def has_active_or_recent_trial_required
    render_404 unless current_organization.show_advanced_security_onboarding?
  end
end
