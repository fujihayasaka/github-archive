# typed: true
# frozen_string_literal: true

require "monolith-twirp-code_scanning-suggested_fixes"

module Api::Internal::Twirp::CodeScanning
  module SuggestedFixes
    module V1
      # Handler for the MonolithTwirp::CodeScanning::SuggestedFixes::V1::SuggestedFixesAPIService
      class SuggestedFixesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["turboscan"]
        handles_service MonolithTwirp::CodeScanning::SuggestedFixes::V1::SuggestedFixesAPIService

        # Public: Implementation of the SuggestedFixStateChanged Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::SuggestedFixes::V1::SuggestedFixStateChangedRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodeScanning::SuggestedFixes::V1::SuggestedFixStateChangedResponse, or a Twirp::Error.
        def suggested_fix_state_changed(req, env)
          repository_id = id_argument(req.repository_id)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless repository_id

          repository = T.cast(::Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          return Twirp::Error.invalid_argument("repository does not exist") if repository.nil?
          return Twirp::Error.aborted("GHAS is not usable") unless CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository:)

          pull_request_id = id_argument(req.pull_request_id)
          pull_request = PullRequest.find_by(repository:, id: pull_request_id) if pull_request_id
          if pull_request
            GitHub.logger.info(
              "Notify PR websocket channel as suggested fix state changed",
              "code.namespace": "CodeScanning",
              "code.function": "suggested_fix_state_changed",
              "gh.repo.id": repository_id,
              "gh.pull_request.id": pull_request_id,
              "gh.pull_request.number": pull_request.number,
            )

            channel = GitHub::WebSocket::Channels.pull_request(pull_request)
            GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)
          end

          req.alert_numbers.each do |alert_number|
            GitHub.logger.info(
              "Notify alert websocket channel as suggested fix state changed",
              "code.namespace": "CodeScanning",
              "code.function": "suggested_fix_state_changed",
              "gh.repo.id": repository_id,
              "gh.turboscan.alert_number": alert_number,
            )

            channel = GitHub::WebSocket::Channels.code_scanning_alert(repository, alert_number:)
            GitHub::WebSocket.notify_repository_channel(repository, channel)
          end

          {}
        end
      end
    end
  end
end
