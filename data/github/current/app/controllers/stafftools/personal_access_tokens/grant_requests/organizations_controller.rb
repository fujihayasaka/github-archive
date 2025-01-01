# typed: true
# frozen_string_literal: true

module Stafftools::PersonalAccessTokens::GrantRequests
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
                        ApplicationRecord::Repositories,
                        ApplicationRecord::Configurations

    depends_on_clusters ApplicationRecord::Copilot,
                        only: [:index, :show], optional: true

    def index
      render "stafftools/personal_access_tokens/grant_requests/index", locals: {
        grant_requests: paginated_grant_requests
      }
    end

    def show
      render "stafftools/personal_access_tokens/grant_requests/show", locals: {
        grant: current_grant_request.grant, grant_request: current_grant_request
      }
    end

    private

    def current_target_type
      "Organization"
    end
  end
end
