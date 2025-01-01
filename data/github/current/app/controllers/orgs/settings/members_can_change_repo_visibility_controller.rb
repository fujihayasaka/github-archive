# typed: true
# frozen_string_literal: true

class Orgs::Settings::MembersCanChangeRepoVisibilityController < Orgs::Controller
  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    notice = if params[:members_can_change_repo_visibility] == "1"
      current_organization.allow_members_to_change_repo_visibility(actor: current_user)
      "Members can now change repository visibility."
    else
      current_organization.block_members_from_changing_repo_visibility(actor: current_user)
      "Members can no longer change repository visibility."
    end

    redirect_to :back, notice: notice
  end
end
