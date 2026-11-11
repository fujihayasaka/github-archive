# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class IsCopilotAssociatedRef
        attr_reader :req

        def self.call(req)
          new(req).call
        end

        def initialize(request)
          @req = request
        end

        # Returns true if the ref was created by copilot-swe-agent for the provided repo
        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if req.repository_id.nil? || req.repository_id == 0
          return Twirp::Error.invalid_argument("must be non-empty", argument: "ref") if req.ref.blank?
          return Twirp::Error.not_found("repository not found") unless repository
          return Twirp::Error.not_found("ref not found") unless ref

          branch_creation_push = find_branch_creation_push
          return Twirp::Error.not_found("branch creation push not found") unless branch_creation_push

          if is_copilot_associated_push(branch_creation_push)
            GitHub.logger.info("found copilot associated branch creation push", logging_context)
            return { is_copilot_associated: true }
          end

          latest_push = find_latest_push
          return Twirp::Error.not_found("latest push not found") unless latest_push

          if is_copilot_associated_push(latest_push)
            GitHub.logger.info("found copilot associated latest push", logging_context)
            return { is_copilot_associated: true }
          end

          { is_copilot_associated: false }
        end

        private

        def logging_context
          {
            "code.namespace" => self.class.name,
            "code.function" => "call",
            "gh.request_id" => GitHub.context[:request_id],
            "gh.catalog_service" => "github/actions",
            "gh.repo.id" => req.repository_id,
            "gh.actions.request.ref" => req.ref,
          }
        end

        def find_branch_creation_push
          Repositories.domain.pushes.by_activity_filters(
            repository_id: repository.id,
            sort: GH::Pagination::Sort::Direction::DESC,
            pagination: GH::Pagination::Cursor.new(first: 1),
            ref: ref.qualified_name,
            activity_type: "branch_creation",
          ).first
        end

        def find_latest_push
          Repositories.domain.pushes.latest_by_after_and_ref(
            repository_id: repository.id,
            ref: ref.qualified_name,
          )
        end

        def is_copilot_associated_push(push)
          return false unless copilot_swe_agent
          push.pusher_id == copilot_swe_agent.bot_id
        end

        def repository
          return @repository if @repository
          @repository = Repositories::Public.find_active(req.repository_id)
        end

        def ref
          return @ref if @ref
          @ref = repository.refs.find(req.ref)
        end

        def copilot_swe_agent
          return @copilot_swe_agent if defined?(@copilot_swe_agent)
          @copilot_swe_agent = ::Apps::Privileged.integration(:copilot_swe_agent)
        end
      end
    end
  end
end
