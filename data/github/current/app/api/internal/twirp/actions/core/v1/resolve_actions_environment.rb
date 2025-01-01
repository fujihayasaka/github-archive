# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class ResolveActionsEnvironment
        attr_reader :environment, :repo

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          database_id = Platform::Helpers::NodeIdentification.from_global_id(request.repository_id.global_id).last

          @repo = if GitHub.flipper[:repos_domain_twirp].enabled?
            Repositories.domain.by_id(database_id)
          else
            Repository.find_by(id: database_id)
          end
          @environment = repo&.environments&.find_by(name: request.environment)
        end

        def call
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repo
          return Twirp::Error.not_found("environment does not exist", argument: "environment") unless environment

          {
            environment: {
              name: environment.name,
              environment_id: {
                global_id: get_global_id,
              }
            }
          }
        end

        def get_global_id
          use_next_gid = !GitHub.enterprise?
          use_next_gid ? environment.next_global_id : environment.global_relay_id
        end
      end
    end
  end
end
