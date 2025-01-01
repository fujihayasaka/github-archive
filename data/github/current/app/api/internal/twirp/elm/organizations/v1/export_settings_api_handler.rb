# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-organizations"

module Api::Internal::Twirp::Elm
  module Organizations
    module V1
      # Handler for the MonolithTwirp::Elm::Organizations::V1::ExportSettingsAPIService
      class ExportSettingsAPIHandler < Api::Internal::Twirp::Handler

        handles_service MonolithTwirp::Elm::Organizations::V1::ExportSettingsAPIService
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]

        # Public: Implementation of the ExportRepositoryDefaults Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Organizations::V1::ExportRepositoryDefaultsRequest.
        #
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Elm::Organizations::V1::ExportRepositoryDefaultsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Elm::Organizations::V1::ExportRepositoryDefaultsRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def export_repository_defaults(req, env)
          organization_id = id_argument(req.organization_id)
          return Twirp::Error.invalid_argument("missing organization_id", argument: "organization_id") unless organization_id.present?

          organization = Organization.find_by(id: organization_id)
          return Twirp::Error.not_found("organization not found") unless organization.present?

          {
            repository_defaults: {
              user_labels: organization.user_labels.map do |label|
                {
                  name: label.name,
                  color: label.color,
                  description: label.description
                }
              end
            }
          }
        end
      end
    end
  end
end
