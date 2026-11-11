# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Evaluates actions rulesets for a given repository, event and actor and
      # returns whether the workflow run is allowed, along with violation details
      # for both enforce and evaluate modes.
      class EvaluateActionsRuleset
        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @request = request
        end

        def call
          repo = find_repository
          return repo if repo.is_a?(Twirp::Error)

          actor = find_actor
          return actor if actor.is_a?(Twirp::Error)

          integration = find_integration(repo)
          return integration if integration.is_a?(Twirp::Error)

          event = ActionsRules::WorkflowRunEvent.new(repo, actor, @request.event_name, integration: integration)
          suites = RuleEngine::GenericEvaluator.evaluate_rules(event)

          response = build_response(suites)
          instrument_audit_event(repo, actor, suites, response)
          response
        end

        private

        # Emit an audit log event when an Actions workflow execution protection
        # policy is evaluated and produces at least one violation (in either
        # enforce or evaluate mode). No event is emitted when the run passes
        # cleanly, to keep audit log volume bounded.
        def instrument_audit_event(repo, actor, suites, response)
          return if response[:violations].empty?

          GitHub.instrument("actions_policy.evaluate", {
            actor: actor,
            repo: repo,
            org: repo.organization,
            business: repo.owner&.business,
            event_name: @request.event_name.to_s,
            integration_installation_id: @request.integration_installation_id.to_i,
            allowed: response[:allowed],
            ruleset_ids: suites.flat_map { |suite| suite.rule_runs.map { |run| run.repository_ruleset_id } }.compact.uniq,
            violations: response[:violations],
          })
        end

        def find_repository
          Repositories::Public.find_active!(@request.repository_id)
        rescue ActiveRecord::RecordNotFound
          Twirp::Error.not_found("repository not found", argument: "repository_id")
        end

        def find_actor
          User.find(@request.actor_id)
        rescue ActiveRecord::RecordNotFound
          Twirp::Error.not_found("actor not found", argument: "actor_id")
        end

        def find_integration(repo)
          return nil unless @request.integration_installation_id.nonzero?

          installation = IntegrationInstallation.find_by(id: @request.integration_installation_id)
          return Twirp::Error.not_found("integration installation not found", argument: "integration_installation_id") unless installation

          # Validate that the installation is on the same owner as the repository
          unless installation.target == repo.owner
            return Twirp::Error.not_found("integration installation not found", argument: "integration_installation_id")
          end

          installation
        end

        def build_response(suites)
          allowed = suites.all?(&:allowed?)

          violations = suites.flat_map do |suite|
            suite.rule_runs.select { |run| run.failed? || run.evaluate_failed? }.map do |run|
              {
                rule_type: run.rule_type.to_s,
                message: run.message.to_s,
                is_evaluate_mode: run.evaluate_mode?,
              }
            end
          end

          message = violations.map { |v| v[:message] }.reject(&:empty?).join("\n")

          {
            allowed:,
            message:,
            violations:,
          }
        end
      end
    end
  end
end
