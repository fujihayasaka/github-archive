# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependabot-settings"

module Api::Internal::Twirp::Dependabot
  module Settings
    module V1
      # Handler for the MonolithTwirp::Dependabot::Settings::V1::RepositoryAPIService
      class RepositoryAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["dependabot_api"]
        handles_service MonolithTwirp::Dependabot::Settings::V1::RepositoryAPIService

        resolve_tenant_context do |req, _env|
          repository = ::Repositories::Public.find_active(req.id)
          next repository.owner&.business if repository.present?
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        # Public: Implementation of the GetRepositorySettings Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Dependabot::Settings::V1::GetRepositorySettingsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Dependabot::Settings::V1::GetRepositorySettingsResponse, or a Twirp::Error.
        def get_repository_settings(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "id") unless req.id.present? && req.id.nonzero?

          repository = ::Repositories::Public.find_active(req.id)

          return Twirp::Error.not_found("Repository ID '#{req.id}' not found.") unless repository
          if GitHub.flipper[:dependabot_offboard_spammy].enabled?
            return Twirp::Error.not_found("Repository ID '#{req.id}' is spammy.") if repository.spammy? || T.must(repository.owner).spammy?
          end

          {
            id: repository.id,
            dependabot_installed: repository.dependabot_installed?,
            dependabot_config_file_enabled: ::SecurityProduct::DependabotConfigFile.new(repository).enabled?,
            automated_security_updates_enabled: ::SecurityProduct::VulnerabilityUpdates.new(repository).enabled?,
            dependabot_on_actions_enabled: ::SecurityProduct::DependabotOnActions.new(repository).enabled?,
            dependabot_self_hosted_enabled: ::SecurityProduct::DependabotSelfHosted.new(repository).enabled?,
            security_updates_grouping_enabled: ::SecurityProduct::VulnerabilityUpdatesGrouping.new(repository).enabled?,
            actions_fully_enabled: repository.workflow_runs.any?,
          }
        end

        # Public: Implementation of the SetPausedFlagOnRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Dependabot::Settings::V1::SetPausedFlagOnRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Dependabot::Settings::V1::SetPausedFlagOnRepositoryResponse, or a Twirp::Error.
        def set_paused_flag_on_repository(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "id") unless req.id.present? && req.id.nonzero?

          repository = ::Repositories::Public.find_active(req.id)

          return Twirp::Error.not_found("Repository ID '#{req.id}' not found.") unless repository

          ActiveRecord::Base.connected_to(role: :writing) do
            ::Repository::DependabotServiceManager.new(repository).pause
          end

          {
            id: repository.id,
            success: true
          }
        end

        # Public: Implementation of the RemovePausedFlagOnRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Dependabot::Settings::V1::RemovePausedFlagOnRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Dependabot::Settings::V1::RemovePausedFlagOnRepositoryResponse, or a Twirp::Error.
        def remove_paused_flag_on_repository(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "id") unless req.id.present? && req.id.nonzero?

          repository = ::Repositories::Public.find_active(req.id)

          return Twirp::Error.not_found("Repository ID '#{req.id}' not found.") unless repository

          ActiveRecord::Base.connected_to(role: :writing) do
            ::Repository::DependabotServiceManager.new(repository).unpause
          end

          {
            id: repository.id
          }
        end

        # Public: Implementation of the SetActionsRunnerFlagOnRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Dependabot::Settings::V1::SetActionsRunnerFlagOnRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Dependabot::Settings::V1::SetActionsRunnerFlagOnRepositoryResponse, or a Twirp::Error.
        def set_actions_runner_flag_on_repository(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "id") unless req.id.present? && req.id.nonzero?

          repository = ::Repositories::Public.find_active(req.id)

          return Twirp::Error.not_found("Repository ID '#{req.id}' not found.") unless repository

          result = ActiveRecord::Base.connected_to(role: :writing) do
            ::SecurityProduct::DependabotOnActions.new(repository).enable(actor: T.must(repository.owner))
          end

          # !result.error? == false when unable to enable Actions runner for repository ID
          # due to the fact that Action feature not enabled (feature_not_available)
          {
            id: repository.id,
            success: !result.error?
          }
        end

        # Public: Implementation of the RemoveActionsRunnerFlagOnRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Dependabot::Settings::V1::RemoveActionsRunnerFlagOnRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Dependabot::Settings::V1::RemoveActionsRunnerFlagOnRepositoryResponse, or a Twirp::Error.
        def remove_actions_runner_flag_on_repository(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "id") unless req.id.present? && req.id.nonzero?

          repository = ::Repositories::Public.find_active(req.id)

          return Twirp::Error.not_found("Repository ID '#{req.id}' not found.") unless repository

          ActiveRecord::Base.connected_to(role: :writing) do
            ::SecurityProduct::DependabotOnActions.new(repository).disable(actor: T.must(repository.owner))
          end

          {
            id: repository.id
          }
        end

        # Public: Implementation of the SetSelfHostedFlagOnRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Dependabot::Settings::V1::SetSelfHostedFlagOnRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Dependabot::Settings::V1::SetSelfHostedFlagOnRepositoryResponse, or a Twirp::Error.
        def set_self_hosted_flag_on_repository(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "id") unless req.id.present? && req.id.nonzero?

          repository = ::Repositories::Public.find_active(req.id)

          return Twirp::Error.not_found("Repository ID '#{req.id}' not found.") unless repository

          result = ActiveRecord::Base.connected_to(role: :writing) do
            ::SecurityProduct::DependabotSelfHosted.new(repository).enable(actor: T.must(repository.owner))
          end

          # !result.error? == false when unable to enable Actions runner for repository ID
          # due to the fact that Action feature not enabled (feature_not_available)
          {
            id: repository.id,
            success: !result.error?
          }
        end
      end
    end
  end
end
