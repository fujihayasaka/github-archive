# typed: true
# frozen_string_literal: true

module Stafftools
  module BusinessExternalIdentities
    class UnlinkedExternalIdentitiesController < ExternalMembersController
      # Allow a limited subset of necessary actions in GHES
      skip_before_action :dotcom_required, only: [:index, :show]
      before_action :ensure_sso_enabled

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        only: [:index, :show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index, :show],
        optional: true

      def index
        external_identities = this_business.unlinked_external_identities

        if params[:query].present? && unlinked_external_identity_search
          external_identities = external_identities.where(unlinked_external_identity_search, "%#{params[:query]}%")
        end

        render "stafftools/business_external_identities/unlinked_external_identities/index",
          layout: "layouts/stafftools/business",
          locals: { unlinked_identities: external_identities.paginate(page: current_page, per_page: PAGE_SIZE) }
      end

      def show
        external_identity = this_business.unlinked_external_identities.find_by(id: params[:id])
        return render_404 unless external_identity

        render "stafftools/business_external_identities/unlinked_external_identities/show",
          layout: "layouts/stafftools/business", locals: {
            business: this_business,
            external_identity: external_identity,
          }
      end

      def destroy
        external_identity = this_business.unlinked_external_identities.find_by(id: params[:id])
        return render_404 unless external_identity

        payload = {
          business: this_business.slug,
          business_id: this_business.id,
          provider_id: external_identity.provider.id,
          external_identity_guid: external_identity.guid,
          external_identity_name_id: external_identity.name_id,
          external_identity_user_name: external_identity.user_name
        }.merge(GitHub.guarded_audit_log_staff_actor_entry(current_user))

        external_identity.destroy

        this_business.instrument_external_identity_revoked(payload)

        flash[:notice] = "External identity with id #{params[:id]} successfully destroyed."
        redirect_to action: :index, slug: this_business.slug
      end
    end
  end
end
