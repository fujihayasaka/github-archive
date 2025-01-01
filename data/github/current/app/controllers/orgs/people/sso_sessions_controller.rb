# typed: true
# frozen_string_literal: true

class Orgs::People::SsoSessionsController < Orgs::Controller
  include IdentityManagement::SsoSessionControllerMethods

  before_action :login_required
  before_action :organization_admin_required
  before_action :sso_enabled_required
  before_action :sso_owner_required
  before_action :person_required

  # Revokes an active SSO session for the member.
  def destroy
    external_identity_session = revoke_external_session(
      target: this_organization,
      actor: current_user,
      subject: person,
      session_id: params[:session_id],
    )

    if request.xhr?
      head :ok
    else
      if external_identity_session.nil?
        flash[:error] = "SSO session could not be found."
      else
        flash[:notice] = "SSO session successfully revoked."
      end
      redirect_to org_person_sso_path(this_organization, person)
    end
  end
end
