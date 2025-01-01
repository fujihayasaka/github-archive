# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetCommitMessage
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
          repo_id = id_argument(req.repository_id)
          if repo_id.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id")
          end

          commit_sha = req.commit_sha
          if commit_sha.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "commit_sha")
          end

          unless repo = Repository.find_by(id: repo_id)
            return Twirp::Error.not_found("repository does not exist", argument: "repository_id")
          end

          begin
            commit = repo.commits.find(commit_sha)
          rescue GitRPC::ObjectMissing
            return Twirp::Error.not_found("commit does not exist in repository", argument: "commit_sha")
          end

          message = commit.message
          if message.length > 1048576
            return Twirp::Error.invalid_argument("commit message is too long", argument: "commit_sha")
          end

          {}.tap do |res|
            res[:commit_message] = message
          end
        end
      end
    end
  end
end
