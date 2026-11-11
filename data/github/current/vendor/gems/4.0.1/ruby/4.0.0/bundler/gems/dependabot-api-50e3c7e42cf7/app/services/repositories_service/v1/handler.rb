# frozen_string_literal: true

module RepositoriesService
  module V1
    class Handler
      def unpause(req, _env)
        github_id = req.repository_github_id
        return Twirp::Error.invalid_argument("repository_github_id is required") if github_id.blank?

        reason = req.reason
        return Twirp::Error.invalid_argument("reason is required") if reason.blank?

        repo = Repo.find_by(github_id: github_id)
        return Twirp::Error.not_found("Could not find repository with github_id=#{github_id}") unless repo

        Activity::PauseManager.new(repo: repo).mark_as_active!(reason)

        {}
      end
    end
  end
end
