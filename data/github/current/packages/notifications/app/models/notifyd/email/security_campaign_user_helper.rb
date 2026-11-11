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
          authorizer.authorized_repository_ids
        end
      end

      # Fetch repo counts for a campaign from the appropriate scanning service (TSS or Turboscan).
      # Returns a Turboscan::Proto::CountsByRepoResponse regardless of campaign type.
      sig { params(security_campaign: SecurityCampaigns::SecurityCampaign, user: User).returns(Turboscan::Proto::CountsByRepoResponse) }
      def self.fetch_repo_counts(security_campaign:, user:)
        organization = T.must(security_campaign.organization)

        if security_campaign.secret_scanning?
          query_service = SecretScanning::AlertQueryService.for_organization(
            current_user: user,
            user_session: nil,
            organization: organization,
            security_campaign_ids: [security_campaign.id],
          )
          counts_by_repo, has_error, _ = query_service.counts_by_repo
          if has_error
            raise StandardError.new("Failed to fetch secret scanning repo counts")
          end

          # Convert SecretScanning repo counts into Turboscan::Proto::CountsByRepoResponse
          # TODO: remove conversion https://github.com/github/secret-scanning/issues/14381
          repo_counts = counts_by_repo.map do |repo|
            Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
              repository_id: repo.repository_id,
              open_count: repo.unresolved_count,
              closed_count: repo.resolved_count,
            })
          end

          Turboscan::Proto::CountsByRepoResponse.new({
            open_count: repo_counts.sum(&:open_count),
            closed_count: repo_counts.sum(&:closed_count),
            repository_counts: repo_counts,
          })
        else
          query_service = CodeScanning::AlertQueryService.for_organization(
            user:,
            user_session: nil,
            organization: organization,
            security_campaign_ids: [security_campaign.id],
          )
          _, has_error, alerts_response = query_service.counts_by_repo

          if has_error
            raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts")
          end
          alerts_response.data
        end
      end
    end
  end
end
