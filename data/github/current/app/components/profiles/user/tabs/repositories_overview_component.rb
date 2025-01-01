# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Tabs
      class RepositoriesOverviewComponent < Profiles::BaseRepositoriesOverviewComponent

        def blank_title
          parts = [
            user_is_viewer? ? "You don't" : "#{profile_user.display_login} doesn't",
            "have any",
            GitHub.public_repositories_available? && !enterprise_managed_user_enabled? ? "public" : nil,
            "repositories yet.",
          ]

          parts.compact.join(" ")
        end

        def render?
          !GitHub.multi_tenant_enterprise?
        end
      end
    end
  end
end
