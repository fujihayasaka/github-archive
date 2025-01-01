# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationUnlinkedExternalIdentitiesController < Stafftools::ExternalMembersController
  before_action :ensure_user_exists
  before_action :ensure_saml_enabled
  before_action :dotcom_required # org SAML only exists in dotcom, not in GHES

  layout "layouts/stafftools/organization/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    unlinked_external_identities = this_organization.unlinked_external_identities

    if params[:query].present? && unlinked_external_identity_search
      unlinked_external_identities = unlinked_external_identities.where(unlinked_external_identity_search, "%#{params[:query]}%")
    end

    render "stafftools/organization_unlinked_external_identities/index",
      locals: { organization: this_organization, unlinked_external_identities: unlinked_external_identities.paginate(page: current_page) }
  end

  def show
    external_identity = this_organization.unlinked_external_identities.find_by(id: params[:id])
    return render_404 unless external_identity

    render "stafftools/organization_unlinked_external_identities/show", locals: {
      organization: this_organization,
      external_identity: external_identity
    }
  end

  def destroy
    external_identity = this_organization.unlinked_external_identities.find_by(id: params[:id])
    return render_404 unless external_identity

    payload = {
      organization: this_organization.login,
      organization_id: this_organization.id,
      provider_id: external_identity.provider.id,
      external_identity_guid: external_identity.guid,
      external_identity_name_id: external_identity.name_id,
      external_identity_user_name: external_identity.user_name
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(current_user))

    external_identity.destroy

    this_organization.instrument_external_identity_revoked(payload)

    flash[:notice] = "External identity with id #{params[:id]} successfully destroyed."
    redirect_to action: :index
  end

  private

  def this_organization
    this_user
  end

  def ensure_saml_enabled
    render_404 unless this_organization.organization? && this_organization.saml_sso_enabled?
  end
end
