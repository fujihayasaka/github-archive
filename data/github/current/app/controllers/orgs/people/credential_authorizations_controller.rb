# typed: true
# frozen_string_literal: true

class Orgs::People::CredentialAuthorizationsController < Orgs::Controller
  before_action :login_required
  before_action :dotcom_required
  before_action :organization_admin_required
  before_action :sso_enabled_required
  before_action :sso_owner_required
  before_action :person_required

  def destroy
    credential_type = params[:credential_type]

    token = person.oauth_accesses.find_by_id(params[:token_id]) if credential_type == "OauthAccess"
    token = person.public_keys.find_by_id(params[:token_id]) if credential_type == "PublicKey"
    return render_404 if token.nil?

    Organization::CredentialAuthorization.revoke \
      organization: this_organization,
      credential: token,
      actor: current_user

    flash[:notice] = "API and Git access successfully revoked."
    redirect_to org_person_sso_path(this_organization, person)
  end
end
