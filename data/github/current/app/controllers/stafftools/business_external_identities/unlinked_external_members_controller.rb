# typed: true
# frozen_string_literal: true

module Stafftools
  module BusinessExternalIdentities
    class UnlinkedExternalMembersController < ExternalMembersController
      # Allow a limited subset of necessary actions in GHES
      skip_before_action :dotcom_required, only: [:show]
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

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show],
        optional: true

      def show
        render "stafftools/business_external_identities/unlinked_external_members/show",
          layout: "layouts/stafftools/business",
          locals: { members: this_business.batched_unlinked_external_members.paginate(page: current_page, per_page: PAGE_SIZE) }
      end
    end
  end
end
