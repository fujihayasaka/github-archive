# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class WorkflowRule < RefUpdateRule

      def initialize
        super(rule_name: "workflows",
          display_name: "Require workflows to pass before merging",
          description: "Require all changes made to a targeted branch to pass the specified workflows before they can be merged.")
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      def is_user_configurable?(source = nil)
        true
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        if rule_config.param("do_not_enforce_on_create")
          [:creation, :deletion]
        else
          [:deletion]
        end
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:organization]
      end

      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })

        workflow_schema = ParameterSchema::Object.new(name: "workflow_file_reference", display_name: "Required workflow", description: "A workflow that must run for this rule to pass")
        workflow_schema.add_field(ParameterSchema::Field.new(name: "repository_id", display_name: "Repository ID",
           type: :integer, required: true, description: "The ID of the repository where the workflow is defined"))
        workflow_schema.add_field(ParameterSchema::Field.new(name: "path", display_name: "File path",
           type: :string, required: true, description: "The path to the workflow file"))
        workflow_schema.add_field(ParameterSchema::Field.new(name: "sha", display_name: "Sha",
           type: :string, required: false, description: "The commit SHA of the workflow file to use"))
        workflow_schema.add_field(ParameterSchema::Field.new(name: "ref", display_name: "Ref",
           type: :string, required: false, description: "The ref (branch or tag) of the workflow file to use"))
        workflow_schema.add_field(ParameterSchema::Field.new(name: "allow_invalid_path", display_name: "Allow invalid path",
           type: :boolean, required: false, description: "Imported workflow that is allowed to exist in a path other than .github/workflows", default_value: false, internal: true))

        schema.add_field(ParameterSchema::Field.new(name: "do_not_enforce_on_create", display_name: "Do not require workflows on creation",
           type: :boolean, default_value: false, aliases: ["do_not_enforce_workflow_rules_on_creation"],
           description: "Allow repositories and branches to be created if a check would otherwise prohibit it."))

        schema.add_field(ParameterSchema::Array.new(name: "workflows", display_name: "Required workflows",
           required: true, content_type: :object, content_object: workflow_schema, ui_control: "workflows",
           description: "Workflows that must pass for this rule to pass.", validator: method(:ensure_valid_workflows)))
        schema
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        repo = context.repository

        rule_commit = if ref_update.respond_to?(:rule_commit)
          ref_update.try(:rule_commit)
        else
          ref_update.after_commit
        end

        relevant_commits = if rule_commit.merge_commit?
          # If it is a merge commit, all parents of the merge need to have the workflow runs
          parent_commits = context.repository.commits.find(rule_commit.parent_oids).reject do |commit|
            commit.oid == ref_update.before_oid
          end
        else
          [rule_commit]
        end

        check_suites = CheckSuite.where(head_sha: relevant_commits.map(&:oid), repository_id: repo.id).all

        # Validate configuration
        source_and_workflows = rule_configs.flat_map do |config|
          workflows = config.param("workflows")
          workflows.map do |workflow|
            [config.source, workflow]
          end
        end
        validated = RulesEngine::WorkflowsHelper.validate_workflows(source_and_workflows)

        rule_configs.map do |rule_config|
          workflows = rule_config.param("workflows")

          results = workflows.map do |workflow|
            if validated.any? { |result| result[:workflow] == workflow && !result[:valid] }
              next [workflow, :invalid]
            end

            matching_check_suites = check_suites.filter { |cs| WorkflowRule.matches_workflow?(cs, workflow) == true }
            latest_matching_check_suite = matching_check_suites.max_by { |cs| cs.created_at.presence || Time.at(0) }

            result = if latest_matching_check_suite.present?
              if latest_matching_check_suite.completed?
                latest_matching_check_suite.failed? ? :failed : :succeeded
              else
                :pending
              end
            else
              :not_found
            end
            [workflow, result]
          end

          if results.all? { |r| r[1] == :succeeded }
            RuleRun.success(rule_config:, ref_update:)
          else
            failed_or_pending = results.reject { |r| r[1] == :succeeded }

            named_workflows = failed_or_pending.map do |workflow, _|
              Actions::Workflow.where(repository_id: workflow["repository_id"], path: workflow["path"])
            end.reduce(&:or)

            message = if failed_or_pending.all? { |r| r[1] == :invalid }
              "Required workflow configuration invalid"
            elsif failed_or_pending.all? { |r| r[1] == :pending }
              count = failed_or_pending.size
              "Required #{"workflow".pluralize(count)} '#{named_workflows.map { |w| w.name }.join(", ")}' #{"is".pluralize(count)} still running"
            elsif failed_or_pending.all? { |r| r[1] == :not_found }
              count = failed_or_pending.size
              "Required #{"workflow".pluralize(count)} '#{named_workflows.map { |w| w.name }.join(", ")}' #{"is".pluralize(count)} not satisfied"
            else
              failed = results.filter { |r| r[1] == :failed }.map do |result|
                named_workflows.find do |workflow|
                  workflow.repository_id == result[0]["repository_id"] && workflow.path == result[0]["path"]
                end
              end.compact

              "Required #{"workflow".pluralize(count)} '#{failed.map { |w| w.name }.join(", ")}' failed"
            end

            RuleRun.failure(rule_config:, ref_update:, message:)
          end
        end
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T.nilable(Hash)) }
      def ruleset_ui_metadata(rule_config)
        workflows = rule_config.param("workflows")
        return unless workflows

        repos = Repository.active.where(id: workflows.map { |w| w["repository_id"] }.uniq).index_by(&:id)
        db_workflows = workflows.map do |workflow|
          Actions::Workflow.where(repository_id: workflow["repository_id"], path: workflow["path"])
        end.reduce(&:or)&.index_by { |w| [w.repository_id, w.path] } || {}

        results = []
        workflows.each do |workflow|
          db_workflow = db_workflows[[workflow["repository_id"], workflow["path"]]]
          if db_workflow
            results << {
              name: db_workflow.name,
              path: db_workflow.path,
              repository_id: db_workflow.repository_id,
              repository: repos[db_workflow.repository_id]
            }
          elsif workflow["allow_invalid_path"]
            # add in the legacy required workflows who live in an invalid path and thus may not exist in `workflows` table
            results << {
              name: "", # we don't have access to the name so the UI will only show the path
              path: workflow["path"],
              repository_id: workflow["repository_id"],
              repository: repos[workflow["repository_id"]]
             }
          end
        end

        source = rule_config.repository_ruleset&.source
        if source&.is_a?(Organization)
          results = results.filter { |workflow| workflow[:repository]&.organization_id == source.id }
        elsif source&.is_a?(Repository)
          results = results.filter { |workflow| workflow[:repository]&.id == source.id }
        end

        repo_payloads = RulesEngine::WorkflowsHelper.workflow_repo_payloads(results.map { |r| r[:repository] }.compact)

        {
          workflows: results.map do |w|
            { name: w[:name], path: w[:path], repository: repo_payloads[w[:repository_id]] }
          end
        }
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def blocks_new_direct_commits?(rule_config)
        rule_config.param("workflows").any?
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          workflows: T::Array[{ repository_id: Integer, path: String, ref: String, sha: String }],
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_valid_workflows(context, workflows, errors)
        source_and_workflows = workflows.map do |workflow|
          [context.root["ruleset_source"], workflow]
        end
        validated = RulesEngine::WorkflowsHelper.validate_workflows(source_and_workflows)

        validated.filter { |v| !v[:valid] }.each do |result|
          errors << {
            error_code: result[:error_code],
            repo_and_path: "#{result[:workflow]["repository_id"]}/#{result[:workflow]["path"]}",
            message: validation_error_message(result)
          }
        end
      end

      sig do
        params(result: T::Hash[Symbol, T.untyped])
        .returns(T.nilable(String))
      end
      def validation_error_message(result)
        error_code = result[:error_code]

        case error_code
        when :repo_not_found
          "Workflow source repository not found"
        when :actions_sharing_disabled
          "Workflow source repository '#{result[:repo].name_with_display_owner}' has actions sharing disabled"
        when :ref_not_found
          "Workflow source repository '#{result[:repo].name_with_display_owner}' does not have ref: #{result[:workflow]["ref"]}"
        when :sha_not_found
          "Workflow source repository '#{result[:repo].name_with_display_owner}' does not have a reachable SHA: #{result[:workflow]["sha"]}"
        when :workflow_not_found
          "Workflow source repository '#{result[:repo].name_with_display_owner}' does not contain a workflow at: #{result[:workflow]["path"]}"
        when :not_in_org
          "Workflow source repository is not accessible by this organization"
        when :actions_disabled_for_source_repo
          "Actions is disabled for the workflow source repository"
        when :workflow_path_invalid
          "Workflow must be in the .github/workflows directory"
        when :workflow_path_no_subdir
          "Workflow must be in the .github/workflows directory and cannot be in a subdirectory"
        end
      end

      sig { params(check_suite: CheckSuite, workflow: T::Hash[String, T.untyped]).returns(T.any(T::Boolean, Symbol)) }
      def self.matches_workflow?(check_suite, workflow)
        return false unless check_suite.required_workflow?
        return false if check_suite.imposer_repo_id != workflow["repository_id"]
        return false if check_suite.processed_workflow_file_path != workflow["path"]

        if workflow["sha"].present? && workflow["ref"].present?
          return false if check_suite.workflow_run&.workflow_file_checkout_sha != workflow["sha"]
          return false if check_suite.workflow_run&.workflow_file_ref != workflow["ref"]
        elsif workflow["sha"].present?
          return false if check_suite.workflow_run&.workflow_file_checkout_sha != workflow["sha"]

          # workflow_file_ref should never be filled out when the rule config only has a sha
          return false if !check_suite.workflow_run&.workflow_file_ref.nil?
        elsif workflow["ref"].present?
          workflow_file_ref = check_suite.workflow_run&.workflow_file_ref

          # if workflow_file_ref is nil, we return this symbol to indicate that we need to show an error message to the user
          return :run_missing_workflow_file_ref if workflow_file_ref.nil?
          return false if workflow["ref"] != workflow_file_ref
        end

        GitHub.dogstats.increment("repository_rules_engine.rule.workflows.check_suite_match")
        true
      end

      module StatusMethods
        extend T::Sig
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { params(include_optional: T::Boolean).returns(T::Boolean) }
        def workflows_rule_enabled?(include_optional: false)
          configs_by_type("workflows", include_evaluate: include_optional).any?
        end

        sig { params(include_optional: T::Boolean).returns(T::Array[T::Hash[String, T.untyped]]) }
        def required_workflows(include_optional: false)
          configs_by_type("workflows", include_evaluate: include_optional).flat_map do |config|
            config.param("workflows")
          end
        end

        sig { params(sha: T.any(String, T::Array[String]), include_optional: T::Boolean).returns(T::Array[RequiredWorkflowStatusCheckDuckType]) }
        def required_workflow_statuses(sha:, include_optional: false)
          return [] unless workflows_rule_enabled?(include_optional:)
          check_suites = CheckSuite.where(repository: repository, head_sha: sha).to_ary

          workflows_with_config = required_and_optional_workflows_with_config(include_optional:)
          validations = RulesEngine::WorkflowsHelper.validate_workflows(
            workflows_with_config.map { |config, workflow| [config.source, workflow] }, target_repo: repository)

          workflows_with_config.map do |config, workflow|
            validation_result = validations.find { |v| v[:workflow] == workflow }
            check_suite_results = check_suites.group_by { |cs| WorkflowRule.matches_workflow?(cs, workflow) }
            matching_check_suites = check_suite_results[true] || []
            missing_ref_check_suites = check_suite_results[:run_missing_workflow_file_ref] || []
            latest_matching_check_suite = matching_check_suites.max_by { |cs| cs.created_at.presence || Time.at(0) }
            missing_ref_error_code = :run_missing_workflow_file_ref if latest_matching_check_suite.nil? && missing_ref_check_suites.any?

            RequiredWorkflowStatusCheckDuckType.new(workflow, latest_matching_check_suite,
              invalid_code: missing_ref_error_code || validation_result&.fetch(:error_code, nil),
              required: !config.evaluate_mode?)
          end
        end

        private

        sig { params(include_optional: T::Boolean).returns(T::Array[[RepositoryRuleConfiguration, T::Hash[String, T.untyped]]]) }
        def required_and_optional_workflows_with_config(include_optional: false)
          configs_by_type("workflows", include_evaluate: include_optional).flat_map do |config|
            config.param("workflows").map do |workflow|
              [config, workflow]
            end
          end
        end
      end

      # Currently, the PR merge box only knows how to render status checks
      # To get required workflows to render as a status check, we must create a mock
      # for the status check type
      class RequiredWorkflowStatusCheckDuckType
        extend T::Sig

        sig { returns(T.nilable(CheckSuite)) }
        attr_reader :check_suite

        sig { returns(T.nilable(Symbol)) }
        attr_reader :invalid_code

        sig { returns(T::Boolean) }
        attr_reader :required

        def context
          contextual_name
        end

        def initialize(workflow, check_suite, invalid_code: nil, required: true)
          @workflow = workflow
          @actions_workflow = Actions::Workflow.find_by(repository_id: workflow["repository_id"], path: workflow["path"])
          @check_suite = check_suite
          @invalid_code = invalid_code
          @required = required
        end

        def duration_in_seconds
          check_suite&.duration&.floor || 0
        end

        def required_for_pull_request?(pull)
          async_required_for_pull_request?(pull).sync
        end

        def async_required_for_pull_request?(pull)
          Promise.resolve(required)
        end

        def application
          nil
        end

        def integration
          nil
        end

        def creator
          check_suite&.github_app&.bot
        end

        def target_url(pull_request_number: nil)
          check_suite&.permalink(pull_request_number: pull_request_number)
        end

        def state
          if cs = check_suite
            cs.completed? ? (cs.conclusion || StatusCheckConfig::PENDING) : cs.status
          elsif invalid_code.present?
            return StatusCheckConfig::FAILURE if invalid_code == :run_missing_workflow_file_ref
            StatusCheckConfig::STARTUP_FAILURE
          else
            StatusCheckConfig::EXPECTED
          end
        end

        def state_changed_at
          check_suite&.updated_at || Time.now
        end

        def sort_order
          [CheckRun::MAX_NUMBER_VALUE, StatusCheckConfig::STATE_SORT_ORDER[state], @actions_workflow&.name || @workflow["path"]]
        end

        def description
          cs = check_suite
          if cs && cs.completed?
            cs.success? ? "Required workflow passed" : "Required workflow did not pass"
          elsif cs && cs.status == StatusCheckConfig::IN_PROGRESS
            "Required workflow running"
          elsif invalid_code.present?
            case invalid_code
            when :not_in_org
              "Workflow repository is not accessible by this organization"
            when :visibility_mismatch
              "Workflows cannot be required from a less visible repository"
            when :repo_not_found
              "Workflow repository not found"
            when :actions_sharing_disabled
              "Workflow repository has actions sharing disabled"
            when :ref_not_found, :sha_not_found, :workflow_not_found
              "Workflow not found in source repository"
            when :actions_disabled
              "Actions is disabled for this repository"
            when :actions_disabled_for_source_repo
              "Actions is disabled for the workflow source repository"
            when :run_missing_workflow_file_ref
              "Please close and reopen the PR to trigger this workflow"
            else
              "Workflow configuration invalid"
            end
          else
            "Waiting for workflow to run"
          end
        end

        def contextual_name
          @actions_workflow&.name || @workflow["path"]
        end
      end
    end
  end
end
