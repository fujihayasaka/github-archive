# typed: true
# frozen_string_literal: true

class Businesses::People::CredentialAuthorizationsController < Businesses::BusinessController
  before_action :write_enterprise_sso_required
  before_action :dotcom_required
  before_action :person_required
  before_action :sso_enabled_required
  before_action :business_not_downgraded_to_free_plan_required

  # Revoke SSO-authorized credentials for the intersection of
  # organizations which the credential is assigned to, belong to this business,
  # and the current_user has admin rights over. Without the SSO authorization,
  # this credential will not be able access private data via the API or Git for its
  # organization.
  def destroy
    credential_type = params[:credential_type]
    authorizations = if credential_type == "OauthAccess"
      token = person.oauth_accesses.find_by_id(params[:token_id])
      token.credential_authorizations unless token.nil?
    elsif credential_type == "PublicKey"
      token = person.public_keys.find_by_id(params[:token_id])
      token.active_org_credential_authorizations unless token.nil?
    end
    return render_404 if authorizations.nil?

    organizations = authorizations.map(&:organization) & this_business.organizations

    unless this_business.enterprise_managed_user_enabled?
      organizations = organizations & current_user.owned_organizations
    end

    organizations.each do |organization|
      Organization::CredentialAuthorization.revoke \
        organization: organization,
        credential: token,
        actor: current_user
    end

    flash[:notice] = "API and Git access successfully revoked."
    redirect_to enterprise_person_sso_enterprise_path(this_business, person)
  end
end
