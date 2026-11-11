# typed: true
# frozen_string_literal: true

class Orgs::InitialInviteesController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include SignupHelper
  include MarketingMethods
  include Site::MicrosoftAnalyticsDependency

  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  layout "enterprise_funnel"

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  javascript_bundle "signup"
  javascript_bundle "organizations"

  stylesheet_bundle "site"
  stylesheet_bundle :signup

  def show
    render "organizations/signup/invite", locals: {
      plan: current_organization.plan,
    }
  end
end
