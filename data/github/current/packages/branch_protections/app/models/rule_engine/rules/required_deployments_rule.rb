# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RequiredDeploymentsRule < RefUpdateRule

      def initialize
        super(rule_name: "required_deployments",
              display_name: "Require deployments to succeed",
              description: "Choose which environments must be successfully deployed to before refs can be pushed into a ref that matches this rule.")
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:deletion]
      end

      def supported_source_types
        [:repository]
      end

      def is_user_configurable?(source = nil)
        true
      end

      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Array.new(name: "required_deployment_environments", display_name: "Deployment environments", required: true, content_type: :string,
          description: "The environments that must be successfully deployed to before branches can be merged.", ui_control: "required_deployments",
          validator: method(:ensure_valid_deployment_environments)))

        schema
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        required_environments = rule_configs.map { |c| c.param("required_deployment_environments") }.flatten.uniq

        deployments = T.cast(Deployment
          .for_tree_oid(ref_update.after_commit.tree_oid, repository: context.repository)
          .where(environment: required_environments)
          .includes(:latest_status).to_a, T::Array[Deployment])
        successful_deployments = deployments.select { |deployment| deployment.latest_status&.succeeded? }
        missing_deployment_environments = required_environments.difference(successful_deployments.map(&:environment)).to_set

        rule_configs.map do |config|
          evaluation_metadata = create_evaluation_metadata(deployments, config.param("required_deployment_environments").to_set)

          # If any of the required deployment environments were not found for a policy, fail that policy
          if (config.param("required_deployment_environments").to_set & missing_deployment_environments)&.any?
            RuleRun.failure(rule_config: config, ref_update: ref_update,
              message: "Missing successful active #{missing_deployment_environments.to_a.to_sentence} #{"deployment".pluralize(missing_deployment_environments.size)}.",
              evaluation_metadata: evaluation_metadata)
          else
            RuleRun.success(rule_config: config, ref_update: ref_update, evaluation_metadata: evaluation_metadata)
          end
        end
      end

      def insights_ui_metadata(rule_run)
        if rule_run.evaluation_metadata.present?
          return nil unless rule_run.evaluation_metadata["deployment_results"]
          deployment_results = rule_run.evaluation_metadata["deployment_results"].filter do |deployment_result|
            !deployment_result["deployment"].nil?
          end
          return nil unless deployment_results&.any?

          {
            deployment_results: deployment_results.map do |deployment_result|
              next {} unless (deployment = deployment_result["deployment"])

              {
                status: deployment["status"],
                name: deployment["environment"],
                sha: deployment["sha"],
                id: deployment["id"]
              }
            end
          }
        end
      end

      private

      sig { params(deployments: T::Enumerable[Deployment], required: T::Enumerable[String]).returns(T::Hash[Symbol, T.untyped]) }
      def create_evaluation_metadata(deployments, required)
        {
          deployment_results: required.map do |req|
            {
              required: req,
              deployment: deployments.find { |d| d.environment == req }.then do |deployment|
                {
                  id: deployment.id,
                  environment: deployment.environment,
                  sha: deployment.sha,
                  ref: deployment.ref,
                  status: deployment.state
                } if deployment
              end
            }
          end
        }
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          required_deployment_environments: T::Array[String],
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_valid_deployment_environments(context, required_deployment_environments, errors)
        invalid_deployment_environments = T.let([], T::Array[String])
        proposed_deployment_environments = T.let([], T::Array[String])

        proposed_deployment_environments = required_deployment_environments.compact

        return errors if proposed_deployment_environments.empty?

        allowed_deployment_environments = T.let([], T::Array[String])
        proposed_deployment_environments.each do |deployment_environment|
          allowed_deployment_environments.concat(RulesEngine::Suggestions::deployment_environments_for(context.root["ruleset_source"], deployment_environment))
        end


        invalid_deployment_environments = proposed_deployment_environments - allowed_deployment_environments
        return errors if invalid_deployment_environments.empty?

        errors << {
          error_code: :invalid_deployment_environments,
          message: "Invalid deployment environments",
          value: invalid_deployment_environments
        }
      end

      module StatusMethods
        extend T::Helpers
        extend T::Sig

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def required_deployments_enabled?
          configs_by_type("required_deployments").any?
        end

        sig { returns(T::Array[String]) }
        def required_deployment_environments
          configs_by_type("required_deployments")
            .flat_map { _1.param("required_deployment_environments") }
            .uniq
        end
      end
    end
  end
end
