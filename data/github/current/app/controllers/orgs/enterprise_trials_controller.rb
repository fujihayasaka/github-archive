# typed: true
# frozen_string_literal: true

class Orgs::EnterpriseTrialsController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods

  javascript_bundle :signup
  javascript_bundle :organizations

  before_action :login_required
  before_action :dotcom_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: %i(new)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  def new
    view = Orgs::SetupView.new \
      current_user: current_user,
      plan: GitHub::Plan.business_plus,
      organization: current_organization
    render "organizations/new_enterprise_trial", locals: { view: view }
  end

  def create
    enterprise_trial_for_existing_org_and_redirect(current_organization)
  end
end
