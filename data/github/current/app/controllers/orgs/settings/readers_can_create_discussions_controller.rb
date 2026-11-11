# typed: true
# frozen_string_literal: true

class Orgs::Settings::ReadersCanCreateDiscussionsController < Orgs::Controller
  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    value = params[:readers_can_create_discussions]

    unless %w[0 1].include?(value)
      flash[:error] = "You specified an invalid value for the setting for which users can create discussions."
      return redirect_to(settings_org_member_privileges_path(current_organization))
    end

    notice = if value == "1"
      current_organization.allow_readers_to_create_discussions(actor: current_user)
      "Users with read access to repositories can create new discussions."
    else
      current_organization.block_readers_from_creating_discussions(actor: current_user)
      "Only users with at least triage access to repositories can create new discussions."
    end

    redirect_to settings_org_member_privileges_path(current_organization), notice: notice
  end
end
