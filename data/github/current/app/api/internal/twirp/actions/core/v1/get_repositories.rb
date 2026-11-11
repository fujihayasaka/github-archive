# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetRepositories
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
          user_id = id_argument(req.owner_id)
          if user_id.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "id")
          end

          unless user = User.find_by(id: user_id)
            return Twirp::Error.not_found("user does not exist", argument: "id")
          end

          actions_installation = GitHub.launch_github_app.installations_on(user).first
          return { repositories: [] } unless actions_installation
          {
            repositories: build_repository_list(actions_installation.repositories)
          }
        end

        def build_repository_list(repositories)
          repositories.map do |repository|
            {
              id: repository.id,
              name: repository.name,
              global_relay_id: get_global_id(repository)
            }
          end
        end

        def get_global_id(repository)
          use_next_gid = !GitHub.enterprise?
          use_next_gid ? repository.next_global_id : repository.global_relay_id
        end
      end
    end
  end
end
