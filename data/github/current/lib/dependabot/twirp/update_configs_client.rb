# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class UpdateConfigsClient < Dependabot::Twirp::BaseClient
      def deactivate_update_configs(repository_id:)
        rpc(:DeactivateUpdateConfigs, repository_github_id: repository_id)
      end

      def list_update_configs(repository_id:, owner_id:, config_file_exists:)
        rpc(
          :ListUpdateConfigs,
          repository_github_id: repository_id,
          owner_github_id: owner_id,
          config_file_exists: config_file_exists,
        )
      end

      def repository_status(repository_id:)
        rpc(
          :RepositoryStatus,
          repository_github_id: repository_id
        )
      end

      def resync_config_file(repository_id:, owner_id:)
        rpc(:ResyncConfigFile, repository_github_id: repository_id, owner_github_id: owner_id)
      end

      def trigger_update_job(repository_id:, update_config_id:)
        rpc(
          :TriggerUpdateJob,
          repository_github_id: repository_id,
          update_config_id: update_config_id
        )
      end

      private

      def twirp_class
        DependabotApi::V1::UpdateConfigsClient
      end
    end
  end
end
