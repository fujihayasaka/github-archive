# typed: true
# frozen_string_literal: true

module Stafftools::PersonalAccessTokens::Grants
  class OrganizationsController < AbstractController
    depends_on_clusters ApplicationRecord::Ballast,
                        ApplicationRecord::Billing,
                        ApplicationRecord::Collab,
                        ApplicationRecord::IamAbilities,
                        ApplicationRecord::IssuesPullRequests,
                        ApplicationRecord::Mysql1,
                        ApplicationRecord::Mysql2,
                        ApplicationRecord::Mysql5,
                        ApplicationRecord::NotificationsEntries,
                        ApplicationRecord::Permissions,
                        ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :show], optional: true

    def index
      render "stafftools/personal_access_tokens/grants/index", locals: { grants: paginated_grants }
    end

    def show
      render "stafftools/personal_access_tokens/grants/show", locals: { grant: current_grant }
    end

    private

    def current_target_type
      "Organization"
    end
  end
end
