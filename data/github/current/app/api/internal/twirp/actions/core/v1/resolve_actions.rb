# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class ResolveActions
        extend T::Sig

        attr_reader :req, :env

        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          if @req.actions.empty? || @req.workflow_run_id.blank? || @req.workflow_repo_id.blank? || @req.job_id.blank?
            GitHub.dogstats.increment(
              "api_twirp.actions.resolve_action",
              tags: ["connect:false", "error:invalid_argument"]
            )
          end

          return Twirp::Error.invalid_argument("must be non-empty", argument: "actions") if @req.actions.empty?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "workflow_run_id") if @req.workflow_run_id.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "workflow_repo_id") if @req.workflow_repo_id.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "job_id") if @req.job_id.blank?

          if !GitHub.actions_enabled?
            return Twirp::Error.not_found(404, message: "Unable to resolve actions: GitHub Actions is not enabled")
          end

          workflow_repo = Repository.find_by(id: @req.workflow_repo_id)
          unless workflow_repo
            return Twirp::Error.invalid_argument("must exist", argument: "workflow_repo_id")
          end
          workflow_repo = T.must(workflow_repo)

          resolve_immutable_actions = workflow_repo.feature_enabled?(:resolve_immutable_actions) || T.must(workflow_repo.owner).feature_enabled?(:resolve_immutable_actions)

          log_fields = {
            :catalog_service => "github/actions-sudo",
            "gh.actions.resolver" => resolve_immutable_actions ? "twirp_v2" : "twirp_v1"
          }

          GitHub.logger.with_named_tags(log_fields) do
            if resolve_immutable_actions
              resolver = Actions::Resolver::V2::TwirpResolver.new(
                workflow_repo: workflow_repo,
                workflow_run_id: @req.workflow_run_id,
                job_id: @req.job_id,
                should_instrument_request: @req.should_instrument_request)

              begin
                resolver.resolve(@req.actions.to_a)
              rescue PackageRegistry::Twirp::Error, ContainerRegistry::Twirp::Error => e
                Failbot.report(e)
                GitHub.logger.error("failed to resolve actions due to twirp error", e)

                Twirp::Error.internal("Failed to resolve actions")
              end
            else
              resolver = Actions::Resolver::V1::TwirpResolver.new(
                workflow_repo: workflow_repo,
                workflow_run_id: @req.workflow_run_id,
                job_id: @req.job_id,
                should_instrument_request: @req.should_instrument_request)

              resolver.resolve(@req.actions.to_a)
            end
          end
        end
      end
    end
  end
end
