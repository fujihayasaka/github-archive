# typed: strict
# frozen_string_literal: true

module Orgs
  module Autocomplete
    class RepositoryPermissionsController < Orgs::Controller
      before_action :login_required
      before_action :ensure_trade_restrictions_allows_org_settings_access

      depends_on_clusters ApplicationRecord::Iam,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Copilot

      sig { void }
      def index
        render json: RepoRoleFgps.fgps_payload(this_organization)
      end
    end
  end
end
