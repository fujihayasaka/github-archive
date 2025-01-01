# typed: true
# frozen_string_literal: true

class Businesses::People::SsoSessionsController < Businesses::BusinessController
  include IdentityManagement::SsoSessionControllerMethods

  before_action :write_enterprise_sso_required
  before_action :person_required
  before_action :sso_enabled_required
  before_action :business_not_downgraded_to_free_plan_required

  # Revoke an active SSO session for the member
  def destroy
    revoke_external_session(
      target: this_business,
      actor: current_user,
      subject: person,
      session_id: params[:session_id]
    )

    if request.xhr?
      head :ok
    else
      flash[:notice] = "SSO session successfully revoked."
      redirect_to enterprise_person_sso_enterprise_path(this_business, person)
    end
  end
end
