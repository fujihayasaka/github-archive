# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class SecurityCampaignUserHelper
      sig { params(user: User, security_campaign: SecurityCampaigns::SecurityCampaign, repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
      def self.enabled_repository_ids(user:, security_campaign:, repository_ids:)
        GitHub.dogstats.distribution_time("security_campaigns.security_campaigns_user_enabled_repository_ids") do
          # Find the set of the repositories the user has read_code_scanning permission on
          authorizer = SecurityProduct::AuthorizationEnumerator.new(user:, actions: [:read_code_scanning], options: {
            organization: security_campaign.organization,
            repository_ids:,
          })
          accessible_repository_ids = authorizer.authorized_repository_ids

          # filter for repos that notifications have been enabled
          GitHub.newsies.subscribed_repository_ids(user.id, accessible_repository_ids, SecurityAlert.name)
        end
      end
    end
  end
end
