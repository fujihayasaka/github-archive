# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class IsDependabotAssociatedRef
        NO_REPO_FOUND_MESSAGE = "no repo found for database id"
        NO_REF_FOUND_MESSAGE = "no ref found in repository"
        REF_FOUND_MESSAGE = "found dependabot association"

        attr_reader :req

        def self.call(req)
          new(req).call
        end

        def initialize(request)
          @req = request
        end

        # Returns true if the ref is associated with a dependabot pull request for the provided repo
        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if req.repository_id.nil? || req.repository_id == 0
          return Twirp::Error.invalid_argument("must be non-empty", argument: "ref") if req.ref.blank?

          log_fields = {
            "code.namespace" => self.class.name,
            "code.function" => "call",
            "gh.request_id" => GitHub.context[:request_id],
            "gh.catalog_service" => "github/actions",
            "gh.repo.id" => req.repository_id,
            "gh.actions.request.ref" => req.ref,
          }

          unless repository
            GitHub.logger.info(NO_REPO_FOUND_MESSAGE, log_fields)
            return Twirp::Error.not_found(NO_REPO_FOUND_MESSAGE)
          end

          unless ref
            GitHub.logger.info(NO_REF_FOUND_MESSAGE, log_fields)
            return Twirp::Error.not_found(NO_REF_FOUND_MESSAGE)
          end

          log_fields["git.ref"] = ref.qualified_name

          associated_dependabot_pr = find_dependabot_associated_pr(ref)

          if associated_dependabot_pr
            dependabot_associated_ref = true
            log_fields["gh.pull_request.number"] = associated_dependabot_pr.number
            GitHub.logger.info(REF_FOUND_MESSAGE, log_fields)
          else
            dependabot_associated_ref = false
          end

          {
            is_dependabot_associated: dependabot_associated_ref
          }
        end

        def find_dependabot_associated_pr(ref)
          dependabot_bot_id = GitHub.dependabot_github_app&.bot&.id
          # return early if dependabot isn't setup (ghes)
          return nil unless dependabot_bot_id

          ::PullRequest.where(
            repository_id: ref.repository.id,
            head_ref: Git::Ref.safe_ref_name(ref_names: ref.qualified_name),
            user_id: dependabot_bot_id,
          ).take
        end

        def repository
          return @repository if @repository

          begin
            @repository = Repositories::Public.find_active!(req.repository_id)
          rescue ActiveRecord::RecordNotFound
          end
        end

        def ref
          return @ref if @ref

          begin
            @ref = repository.refs.find(req.ref)
          rescue ActiveRecord::RecordNotFound
          end
        end

      end
    end
  end
end
