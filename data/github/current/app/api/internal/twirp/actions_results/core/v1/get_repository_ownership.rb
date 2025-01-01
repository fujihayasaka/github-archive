# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      class GetRepositoryOwnership
        attr_reader :req, :env

        def self.call(request, env)
          new(request, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository

          owners = ActionsPolicyHelper.get_relevant_entities(entity: repository, include_self: true)

          {
            customer_id: Billing::EntityResolver.customer_id(repository),
            repository_hierarchy: ActionsPolicyHelper.entities_to_primitives(owners)
          }
        end

        private

        def repository
          @repository ||= Repositories.domain.by_id(req.repository_id)
        end
      end
    end
  end
end
