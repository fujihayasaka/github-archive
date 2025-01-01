# typed: true
# frozen_string_literal: true

require "monolith-twirp-support-helphub"

module Api::Internal::Twirp::Support
  module HelpHub
    module V1
      # Provides access to Support-relevant lfs context
      class LfsSupportAPIHandler < Api::Internal::Twirp::Handler
        handles_service(MonolithTwirp::Support::HelpHub::V1::LfsSupportAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        REPOSITORY_LOOKUP_LIMIT = 200

        # Public: Implementation of the GetLFSInfoForOrganizastion Twirp RPC.
        #
        # req - The Twirp request as a HelpHub::V1::GetLfsInfoForUserRequest
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, returns lfs usage for organization
        # with repository breakdown. Returns a HelpHub::V1::GetLfsInfoForUserResponse
        def get_lfs_info_for_user(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          { lfs: build_lfs_owner_information(user) }
        end

        # Public: Implementation of the GetLFSInfoForOrganizastion Twirp RPC.
        #
        # req - The Twirp request as a HelpHub::V1::GetLfsInfoForOrganizationRequest
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, returns lfs usage for organization
        # with repository breakdown. Returns a HelpHub::V1::GetLfsInfoForOrganizationResponse
        def get_lfs_info_for_organization(req, env)
          organization_id = id_argument(req.organization_id, env[:organization_id])
          unless organization_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          organization = Organization.find_by(id: organization_id)
          if organization.nil?
            return Twirp::Error.not_found("organization does not exist", argument: "organization_id")
          end

          { lfs: build_lfs_owner_information(organization) }
        end

        private

        # Private: Creates lfs owner information hash
        #
        # owner - A user/ organization object
        #
        # Returns a Hash that matches the twirp definition
        def build_lfs_owner_information(owner)
          asset_status = owner.asset_status || owner.build_asset_status
          {
            is_lfs_enabled: owner.git_lfs_enabled?,
            disabled_because_over_quota: asset_status.over_bandwidth_quota? || asset_status.over_storage_quota?,
            bandwidth_usage_gb:  asset_status.bandwidth_usage,
            bandwidth_quota_gb: asset_status.bandwidth_quota,
            storage_usage_b: (asset_status.storage * 1.gigabyte).round,
            storage_quota_b: (asset_status.storage_quota * 1.gigabyte).round,
            repositories: build_lfs_repository_list(owner)
          }
        end

        # Private: Given an owner, build a list of "busy" repositories using LFS with their usage information
        #
        # owner - A user / organization object
        #
        # Returns an array of hashes that match the twirp definition for the LFS Repository
        def build_lfs_repository_list(owner)
          lfs_networks = Platform::Loaders::LfsNetworksByUsage.load(owner.id).sync
          busy_repos = Repository.where(owner_id: owner.id, parent_id: nil, active: true, locked: false)
            .order(pushed_at: :desc)
            .limit(REPOSITORY_LOOKUP_LIMIT)

          networks_with_lfs_ids = Media::Blob.verified
            .distinct
            .where(repository_network_id: busy_repos.map(&:network_id))
            .limit(100)
            .pluck(:repository_network_id)

          lfs_disk_usage = Platform::Loaders::NetworkLfsDiskUsage.new.fetch(networks_with_lfs_ids)

          busy_repos.select { |repo| repo.network_id.in?(networks_with_lfs_ids) }.map do |repo|
            bw = lfs_networks && lfs_networks[repo.network_id]
            {
              repository_id: repo.id,
              nwo: repo.name_with_owner,
              bandwidth_gb: bw&.dig(:bandwidth_down),
              disk_usage_b:  lfs_disk_usage[repo.network_id] || 0
            }
          end
        end
      end
    end
  end
end
