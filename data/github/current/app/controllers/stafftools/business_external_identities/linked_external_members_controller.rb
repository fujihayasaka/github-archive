# typed: true
# frozen_string_literal: true

module Stafftools
  module BusinessExternalIdentities
    class LinkedExternalMembersController < ExternalMembersController
      # Allow a limited subset of necessary actions in GHES
      skip_before_action :dotcom_required, only: [:show]
      before_action :ensure_sso_enabled

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      def show
        external_identities = this_business.external_provider.external_identities

        if params[:query].present? && external_identity_search
          external_identities = external_identities.where(external_identity_search, "%#{params[:query]}%")
        end

        members_ids = external_identities.user_identities.pluck(:user_id)

        users = if params[:query].present? && external_user_search
          ::User.batched_scope(:id, values: members_ids) { |scope| scope.where(external_user_search, "%#{params[:query]}%") }
        else
          ::User.batched_scope(:id, values: members_ids)
        end

        users = users.order(:login)

        render "stafftools/business_external_identities/linked_external_members/show",
          layout: "layouts/stafftools/business",
          locals: { members: users.paginate(page: current_page, per_page: PAGE_SIZE) }
      end
    end
  end
end
