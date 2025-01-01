# typed: true
# frozen_string_literal: true

class Orgs::Settings::TeamCreationController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods

  before_action :login_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    notice = if params[:members_can_create_teams] == "1"
      current_organization.allow_members_to_create_teams(actor: current_user)
      "Members can now create teams."
    else
      current_organization.block_members_from_creating_teams(actor: current_user)
      "Members can no longer create teams."
    end

    redirect_to :back, notice: notice
  end
end
