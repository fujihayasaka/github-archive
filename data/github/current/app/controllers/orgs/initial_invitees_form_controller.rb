# typed: true
# frozen_string_literal: true

class Orgs::InitialInviteesFormController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include SignupHelper
  include MarketingMethods
  include Site::MicrosoftAnalyticsDependency

  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only

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

  javascript_bundle "signup"
  javascript_bundle "organizations"

  stylesheet_bundle :signup

  def show
    render "organizations/signup/invite_form", layout: false, locals: {
      organization: current_organization,
      per_seat_pricing_model: per_seat_pricing_model,
    }
  end
end
