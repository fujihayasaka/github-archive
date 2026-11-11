# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationExternalIdentitiesController < Stafftools::ExternalMembersController
  before_action :ensure_user_exists
  before_action :ensure_saml_enabled
  before_action :dotcom_required, only: [:destroy]

  layout "layouts/stafftools/organization/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index],
    optional: true

  def index
    view = create_view_model(
      Stafftools::Organization::SamlSettingsView,
      organization: this_organization,
      filter: params[:scope],
      page: params[:page] || 1,
      query: params[:query],
      external_identity_search: external_identity_search,
      external_user_search: external_user_search,
    )

    render "stafftools/organization_external_identities/index", locals: { view: view }
  end

  def show
    user = User.find_by_login(params[:id])
    return render_404 unless user

    external_identity = this_organization.saml_provider.external_identities.
      linked_to(user).first

    view = create_view_model(
      Stafftools::Organization::ExternalIdentityView,
      organization: this_organization,
      user: user,
      external_identity: external_identity,
    )
    render "stafftools/organization_external_identities/show", locals: { view: view }
  end

  def destroy
    user = User.find_by_login(params[:id])
    return render_404 unless user
    return render_404 unless ExternalIdentity.linked?(provider: this_organization.saml_provider,
                                                      user: user)

    payload = {
      user: user,
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(current_user))

    ExternalIdentity.unlink(
      provider: this_organization.saml_provider,
      user: user,
      instrumentation_payload: payload,
    )

    flash[:notice] = "External identity for #{user} successfully unlinked."
    redirect_to :back
  end

  private

  def this_organization
    this_user
  end

  def ensure_saml_enabled
    render_404 unless this_organization.organization? && this_organization.saml_sso_enabled?
  end
end
