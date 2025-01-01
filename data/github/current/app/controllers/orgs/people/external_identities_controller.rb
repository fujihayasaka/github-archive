# typed: true
# frozen_string_literal: true

class Orgs::People::ExternalIdentitiesController < Orgs::Controller
  before_action :login_required
  before_action :dotcom_required
  before_action :organization_admin_required
  before_action :sso_enabled_required
  before_action :sso_owner_required
  before_action :person_required

  def destroy
    ExternalIdentity.unlink(
      provider: this_organization.external_identity_session_owner.saml_provider,
      user: person,
      instrumentation_payload: {
        actor: current_user,
        user: person,
      },
    )

    flash[:notice] = "External identity for #{person} successfully revoked."
    redirect_to org_person_sso_path(this_organization, person)
  end
end
