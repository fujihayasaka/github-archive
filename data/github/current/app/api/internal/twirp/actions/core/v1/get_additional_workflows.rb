# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetAdditionalWorkflows
        include GitHub::Tracing

        REPO_NOT_FOUND_MESSAGE = "repository not found for the given database id"
        MISSING_RULESET_ARGS_MESSAGE = "Missing required arguments to retrieve workflow rulesets"

        attr_reader :req, :env

        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        # Returns the additional workflows that need to be enforced
        # for a webhook event in the repository. This currently
        # returns only ruleset workflows but can easily be extended
        # to return other workflows provided by various integrations
        trace_method :call
        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id") if @req.repository_id.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "event_type") if @req.event_type.blank?

          repo = if GitHub.flipper[:repos_domain_twirp].enabled?
            Repositories.domain.by_id(@req.repository_id)
          else
            Repository.find_by(id: @req.repository_id)
          end

          unless repo
            GitHub.logger.info(
              REPO_NOT_FOUND_MESSAGE,
              "code.namespace" => "GetAdditionalWorkflows",
              "code.function" => "call",
              "gh.request_id" => GitHub.context[:request_id],
              "service.name" => "github/actions_experience",
            )
            return Twirp::Error.not_found(REPO_NOT_FOUND_MESSAGE)
          end

          additional_workflows_for_repository(repo, @req.event_type)
        end

        private

        def additional_workflows_for_repository(repo, event_type)
          return {} unless repo.owner.is_a?(Organization)

          additional_workflows = {}

          if ruleset_args_present?
            additional_workflows[:ruleset_workflows] = retrieve_ruleset_workflows(repo, event_type)
          else
            GitHub.logger.info({
              message: "missing ruleset args for event: #{event_type}",
              fn: "get_additional_workflows.additional_workflows_for_repository_new_format",
              repo: repo.name_with_owner,
            })
          end

          additional_workflows
        end

        def retrieve_ruleset_workflows(repo, event_type)
          AdditionalWorkflowsProvider::RulesetWorkflowsProvider
          .new(repo, event_type, @req.base_ref, @req.before_oid, @req.after_oid)
          .retrieve_ruleset_workflows
        end

        def ruleset_args_present?
          @req.base_ref.present? && @req.before_oid.present? && @req.after_oid.present?
        end
      end
    end
  end
end
