# typed: true
# frozen_string_literal: true

class Orgs::UpgradeIgnoresController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def create
    current_organization.upgrade_ignore = current_organization.plan.name
    current_organization.save
    redirect_to org_dashboard_path(current_organization)
  end
end
