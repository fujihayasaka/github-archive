# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::DeployKeyAPIService
      class DeployKeyAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::DeployKeyAPIService
        allow_access_for :client, allowed_clients: %w[octoshift git_src_migrator]

        # Public: Implementation of the CreateDeployKey Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::CreateDeployKeyRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::CreateDeployKeyResponse, or a Twirp::Error.
        def create_deploy_key(req, env)
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          if req.verifier_user_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "verifier_user_id")
          end

          if req.title.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "title")
          end

          if req.key.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "key")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          return Twirp::Error.not_found("Repository '#{req.repository_id}' was not found.") unless repository && repository.active?

          verifier_user = replica(User).find_by(id: req.verifier_user_id)
          return Twirp::Error.not_found("Verifier user '#{req.verifier_user_id}' was not found.") unless verifier_user

          deploy_key_attributes = {
            title: req.title,
            key: req.key,
            verifier: verifier_user,
            read_only: !req.is_write_enabled.value,
            octoshift_bypass_deploy_key_policy: true,
          }

          deploy_key = ActiveRecord::Base.connected_to(role: :writing) do
            repository.public_keys.create_with_verification(deploy_key_attributes)
          end

          if deploy_key.valid?
            # The deploy key was created successfully, and with the bypasses_policy attribute set to true (above).
            # Instrument if the org/enterprise has disabled the policy so we have a record of the bypass.
            instrument_deploy_key_bypass(repository, verifier_user)
            build_deploy_key_hash(deploy_key)
          else
            Twirp::Error.canceled("Could not create deploy key: #{deploy_key.errors.full_messages.join(", ")}")
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the DeleteDeployKey Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::DeleteDeployKeyRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::DeleteDeployKeyResponse, or a Twirp::Error.
        def delete_deploy_key(req, env)
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          if req.deploy_key_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "deploy_key_id")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          return Twirp::Error.not_found("Repository '#{req.repository_id}' was not found.") unless repository && repository.active?

          deploy_key = replica(PublicKey).find_by(repository_id: repository.id, id: req.deploy_key_id)
          return Twirp::Error.not_found("Deploy key '#{req.deploy_key_id}' was not found.") unless deploy_key

          ActiveRecord::Base.connected_to(role: :writing) do
            deploy_key.destroy_with_explanation(:removed_by_staff)
          end

          # Return nothing
          {}
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def build_deploy_key_hash(deploy_key)
          {
            id: deploy_key.id,
          }
        end

        def instrument_deploy_key_bypass(repository, user)
          return if repository.nil?
          disabled, _ = repository.deploy_keys_disabled_by_policy_with_policy_source
          # We only want to instrument if the associated enterprise/organization has disabled the policy
          # This truly means the policy was bypassed
          if disabled
            payload = {
              user: user,
              repository: repository,
              reason: "Deploy key policy was bypassed by GitHub Enterprise Importer for imports"

            }
            GitHub.instrument "deploy_key_policy.bypass", payload
          end
        end
      end
    end
  end
end
