# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetRepositoryOwners
        include Api::Internal::Twirp::Actions::Core::V1::ActorsDependency
        include Api::Internal::Twirp::Actions::Core::V1::ArgumentsDependency

        attr_reader :req, :env

        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          repo_id = id_argument(req.id)
          if repo_id.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "id")
          end

          unless repo = Repository.find_by(id: repo_id)
            return Twirp::Error.not_found("repository does not exist", argument: "id")
          end

          owner = repo.owner
          if owner.blank?
            return Twirp::Error.not_found("repository owner is nil", argument: "id")
          end

          {}.tap do |res|
            res[:repository] = build_actor(repo)
            res[:owner] = build_actor(owner)
            res[:owner_plan_name] = repo.async_actions_plan_owner.sync.plan_name
            res[:business] = build_actor(owner.business) if owner.business
          end
        end
      end
    end
  end
end
