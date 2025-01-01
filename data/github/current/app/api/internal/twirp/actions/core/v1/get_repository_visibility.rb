# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetRepositoryVisibility
        include GitHub::Memoizer
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
          unless repository
            return Twirp::Error.not_found("repository does not exist", argument: "repository_id")
          end

          {
            visibility: visibility
          }
        end

        private

        memoize def repository
          if GitHub.flipper[:repos_domain_twirp].enabled?
            Repositories.domain.by_id(req.repository_id)
          else
            Repository.find_by(id: req.repository_id)
          end
        end

        sig { returns(Integer) }
        def visibility
          if repository.public?
            MonolithTwirp::Actions::Core::V1::RepositoryVisibility::REPOSITORY_VISIBILITY_PUBLIC
          elsif repository.private? && repository.visibility == Repository::PRIVATE_VISIBILITY
            MonolithTwirp::Actions::Core::V1::RepositoryVisibility::REPOSITORY_VISIBILITY_PRIVATE
          elsif repository.internal?
            MonolithTwirp::Actions::Core::V1::RepositoryVisibility::REPOSITORY_VISIBILITY_INTERNAL
          else
            MonolithTwirp::Actions::Core::V1::RepositoryVisibility::REPOSITORY_VISIBILITY_INVALID
          end
        end
      end
    end
  end
end
