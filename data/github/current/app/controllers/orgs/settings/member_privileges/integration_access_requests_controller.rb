# typed: true
# frozen_string_literal: true

class Orgs::Settings::MemberPrivileges::IntegrationAccessRequestsController < Orgs::Controller
  before_action :organization_admin_required

  ALLOW_ACCESS_REQUESTS_SETTINGS = {
    off: "0",
    on: "1",
  }.freeze

  def update
    return render_error unless valid_paramater?

    notice = set_allow_access_requests!

    redirect_to :back, notice: notice
  end

  private

  def valid_paramater?
    ALLOW_ACCESS_REQUESTS_SETTINGS.values.include?(params[:allow_access_requests])
  end

  def render_error
    flash[:error] = "You specified an invalid value for the 'outside collaborators can request third party access' setting."
    redirect_to :back
  end

  def set_allow_access_requests!
    if params[:allow_access_requests] == ALLOW_ACCESS_REQUESTS_SETTINGS[:on]
      current_organization.allow_third_party_access_requests_from_outside_collaborators(actor: current_user)
      "Outside collaborators can now request third party access."
    else
      current_organization.disallow_third_party_access_requests_from_outside_collaborators(actor: current_user)
      "Outside collaborators can no longer request third party access."
    end
  end
end
