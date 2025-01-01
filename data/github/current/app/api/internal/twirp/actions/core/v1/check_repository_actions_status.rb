# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class CheckRepositoryActionsStatus
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

          repo = Repositories.domain.by_id(repo_id)

          invalid_reason = repository_invalid_reason(repo)
          {
            can_use_actions: invalid_reason.blank?,
            reason: invalid_reason
          }
        end

        def repository_invalid_reason(repository)
          return "repository is nil" if repository.nil?
          return "repository owner is nil" if repository.owner.nil?
          return "repository is archived" if repository.archived?
          return "spamminess check is enabled and repository is spammy" if GitHub.spamminess_check_enabled? && repository.spammy?
          return "repository is disabled" if repository.disabled?
          return "repository access is disabled" if repository.access.disabled?
          return "" if repository.active?

          "repository is not active"
        end
      end
    end
  end
end
