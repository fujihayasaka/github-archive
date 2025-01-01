# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class SecurityCampaignUserHelper
      sig { params(user: User, security_campaign: SecurityCampaigns::SecurityCampaign).returns(T::Array[Integer]) }
      def self.enabled_repository_ids(user:, security_campaign:)
        # fetch repository ids for the security campaign
        repository_ids = SecurityCampaigns::SecurityCampaignAlert.where(security_campaign: security_campaign).distinct.pluck(:repository_id)

        # fetch accessible repositories for a user
        associated_repository_ids = Set.new(user.associated_repository_ids(min_action: :read, repository_ids: repository_ids))
        filtered_associated_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
          actor: user,
          repository_ids: associated_repository_ids.to_a,
          resource: "contents",
        )

        accessible_repository_ids = Repositories::Public.accessible_repositories(
          repository_ids: repository_ids, associated_repository_ids: filtered_associated_repository_ids
        ).pluck(:id)

        # filter for repos that notifications have been enabled
        GitHub.newsies.subscribed_repository_ids(user.id, accessible_repository_ids, SecurityAlert.name)
      end
    end
  end
end
