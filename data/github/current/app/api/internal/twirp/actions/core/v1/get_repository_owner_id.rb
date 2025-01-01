# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetRepositoryOwnerId
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

          repo = if GitHub.flipper[:repos_domain_twirp].enabled?
            Repositories.domain.by_id(repo_id)
          else
            Repository.find_by(id: repo_id)
          end

          unless repo
            return Twirp::Error.not_found("repository does not exist", argument: "id")
          end

          if repo.owner.blank?
            return Twirp::Error.not_found("repository owner is nil", argument: "id")
          end

          owner = build_actor(repo.owner)

          if owner.blank?
            return Twirp::Error.not_found("repository owner is nil", argument: "id")
          end

          {}.tap do |res|
            res[:owner_id] = owner[:id]
          end
        end
      end
    end
  end
end
