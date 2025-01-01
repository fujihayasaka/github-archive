# typed: true
# frozen_string_literal: true

module Stafftools
  class BusinessExternalIdentitiesController < Stafftools::BusinessesController

    # Allow a limited subset of necessary actions in GHES
    skip_before_action :dotcom_required, only: %w(
      show
    )

    before_action :ensure_sso_enabled

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      only: [:show]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      only: [:linked_saml_orgs]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show, :linked_saml_orgs], optional: true

    PAGE_SIZE = 100

    def linked_saml_orgs # rubocop:todo GitHub/UseRestfulActions
      render "stafftools/business_external_identities/linked_saml_orgs",
        layout: "layouts/stafftools/business",
        locals: { orgs: this_business.linked_saml_orgs.paginate(page: current_page, per_page: PAGE_SIZE) }
    end

    def show
      user = ::User.find_by!(login: params[:id])
      external_identity = \
        ExternalIdentity.find_by(user: user, provider: this_business.external_provider)

      users_in_organization = nil
      if user.organization? && GitHub.flipper[:enterprise_idp_provisioning].enabled?(this_business)
        external_identities_in_org = this_business.external_provider.external_identities_for_organization(user).user_identities
        users_in_organization = external_identities_in_org.map { |identity| identity.user } unless external_identities_in_org.empty?
      end

      render "stafftools/business_external_identities/show",
        layout: "layouts/stafftools/business", locals: {
          user: user,
          business: this_business,
          external_identity: external_identity,
          users_in_organization: users_in_organization&.paginate(page: current_page, per_page: PAGE_SIZE),
        }
    end

    def destroy
      user = ::User.find_by(login: params[:id])
      return render_404 unless user
      return render_404 unless ExternalIdentity.linked?(provider: this_business.external_provider,
                                                        user: user)

      payload = {
        user: user,
      }.merge(GitHub.guarded_audit_log_staff_actor_entry(current_user))

      ExternalIdentity.unlink(
        provider: this_business.external_provider,
        user: user,
        instrumentation_payload: payload,
      )

      flash[:notice] = "External identity for #{user} successfully unlinked."
      redirect_to :back
    end

    private

    def ensure_sso_enabled
      render_404 unless this_business.external_provider_enabled?
    end
  end
end
