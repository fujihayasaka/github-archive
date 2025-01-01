# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RequiredStatusChecksRule < RefUpdateRule
      include StatusHelper

      def initialize
        super(
          rule_name: "required_status_checks",
          display_name: "Require status checks to pass",
          description: "Choose which status checks must pass before the ref is updated. When enabled, commits must first be pushed to another ref where the checks pass.")
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:repository, :organization]
      end

      sig { params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        return [:creation, :deletion] if rule_config.param("do_not_enforce_on_create")
        [:deletion]
      end

      def warning_map
        {
          merge_multi_parent: "The result of this required status check rule was based on multiple merge commit parents",
          merge_multi_parent_out_of_date: "The result of this required status check rule may be based on an out-of-date merge commit"
        }
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        mq_enabled = context.merge_queue_for(ref_update).present?
        decision_by_config = StatusCheckEvaluator.evaluate(repository: context.repository, ref_update:, rule_configs:, has_merge_queue: mq_enabled)

        decision_by_config.map do |config, decision|
          evaluation_metadata = create_evaluation_metadata(decision)

          next RuleRun.success(rule_config: config, ref_update: ref_update, evaluation_metadata: evaluation_metadata) if decision.rules_fulfilled?

          total_count = decision.status_check_results.size
          unsuccessful_decisions = decision.status_check_results.select { |_, v| v.code != :success }.values

          decisions_by_code = unsuccessful_decisions.group_by(&:code)

          if decisions_by_code[:missing]&.any? || decisions_by_code[:unsuccessful]&.any?
            failed_checks = ((decisions_by_code[:missing] || []) + (decisions_by_code[:unsuccessful] || [])).map(&:reason_check)
            build_failed_run(context, ref_update, config, :required_status_checks, failed_checks, total_count, evaluation_metadata)
          elsif decisions_by_code[:invalid_integration]&.any?
            build_failed_run(context, ref_update, config, :required_status_check_integrations,
              (decisions_by_code[:invalid_integration] || []).map(&:reason_check), total_count, evaluation_metadata)
          else
            # Shouldn't get here, but if we do, fail the rule
            RuleRun.failure(rule_config: config, ref_update: ref_update, message: "Missing required status checks")
          end
        end
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T.nilable(Hash)) }
      def ruleset_ui_metadata(rule_config)
        required_status_checks = rule_config.param("required_status_checks")
        return unless required_status_checks

        integrations = Integration.where(id: required_status_checks.filter_map { |check| check["integration_id"] })

        # TODO: Uses string keys to avoid them being camelized
        {
          integrations: integrations.sort_by(&:name).map do |integration|
            {
              id: integration.id,
              name: integration.name,
              preferred_avatar_url: integration.preferred_avatar_url,
            }.stringify_keys
          end
        }
      end

      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Field.new(name: "strict_required_status_checks_policy", display_name: "Require branches to be up to date before merging",
          type: :boolean, required: true, description: "Whether pull requests targeting a matching branch must be tested with the latest code. This setting will not take effect unless at least one status check is enabled."))

        status_checks_schema = ParameterSchema::Object.new(name: "status_check_configuration", display_name: "Required status check", description: "Required status check")
        status_checks_schema.add_field(ParameterSchema::Field.new(name: "context", display_name: "Context",
          type: :string, required: true, description: "The status check context name that must be present on the commit."))
        status_checks_schema.add_field(ParameterSchema::Field.new(name: "integration_id", display_name: "Integration ID",
          type: :integer, required: false, description: "The optional integration ID that this status check must originate from."))

        schema.add_field(ParameterSchema::Field.new(name: "do_not_enforce_on_create", display_name: "Do not require status checks on creation",
          type: :boolean, default_value: false, description: "Allow repositories and branches to be created if a check would otherwise prohibit it."))

        schema.add_field(ParameterSchema::Array.new(name: "required_status_checks", display_name: "Required status checks",
          required: true, min_elements: 1, content_type: :object, content_object: status_checks_schema, description: "Status checks that are required.",
          ui_control: "required_status_checks", validator: method(:ensure_valid_integrations)))

        schema
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def blocks_new_direct_commits?(rule_config)
        rule_config.param("required_status_checks").any?
      end

      sig { params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_config: RepositoryRuleConfiguration, reason_code: Symbol, unsuccessful_status_checks: T::Array[StatusCheckEvaluator::StatusCheckExpandedType], total_count: Integer, evaluation_metadata: T::Hash[Symbol, T.untyped]).returns(RuleRun) }
      def build_failed_run(context, ref_update, rule_config, reason_code, unsuccessful_status_checks, total_count, evaluation_metadata)
        message = failure_message(reason_code, unsuccessful_status_checks, total_count: total_count)
        payload = instrumentation_payload(unsuccessful_status_checks)
        basis_commit_oid = determine_rejection_basis_commit_sha(context, unsuccessful_status_checks)

        RuleRun.failure(rule_config: rule_config, ref_update: ref_update, message: message,
          evaluation_metadata: { reason_code: reason_code, basis_commit_oid:, instrumentation_payload: payload }.merge(evaluation_metadata))
      end

      sig { params(code: Symbol, unsuccessful_status_checks: T::Array[StatusCheckEvaluator::StatusCheckExpandedType], total_count: Integer).returns(String) }
      def failure_message(code, unsuccessful_status_checks, total_count:)
        case code
        when :required_status_checks
          status_failure_message(unsuccessful_status_checks, total_count: total_count)
        when :required_status_check_integrations
          actor_failure_message(unsuccessful_status_checks)
        else
          raise ArgumentError, "Don't know how to produce a message for code #{code.inspect}"
        end
      end

      sig { params(unsuccessful_status_checks: T::Array[StatusCheckEvaluator::StatusCheckExpandedType], total_count: Integer).returns(String) }
      def status_failure_message(unsuccessful_status_checks, total_count:)
        state_counts = Hash.new(0)

        unsuccessful_status_checks.each { |s| state_counts[s.state] += 1 }

        bad_count = unsuccessful_status_checks.size
        checks_string = "#{bad_count} of #{total_count} required status check".pluralize(total_count)

        case
        when bad_count == 1
          status_check = T.must(unsuccessful_status_checks.first)
          "Required status check \"#{status_check.context}\" is #{StatusCheckConfig.adjective_state(status_check.state)}."
        when state_counts.size == 1
          status_check = T.must(unsuccessful_status_checks.first)
          "#{checks_string} #{"is".pluralize(bad_count)} #{StatusCheckConfig.adjective_state(status_check.state)}."
        else
          state_strings = Status::States
            .map { |s| "#{state_counts[s]} #{StatusCheckConfig.adjective_state(s)}" if state_counts[s] > 0 }
            .compact
          "#{checks_string} #{"has".pluralize(bad_count)} not succeeded: #{state_strings.to_sentence}."
        end
      end

      sig { params(unsuccessful_status_checks: T::Array[StatusCheckEvaluator::StatusCheckExpandedType]).returns(String) }
      def actor_failure_message(unsuccessful_status_checks)
        contexts_string = unsuccessful_status_checks
          .map { |status_check| "\"#{status_check.context}\"" }
          .sort
          .to_sentence

        bad_count = unsuccessful_status_checks.size
        "Required status #{"check".pluralize(bad_count)} #{contexts_string} #{"was".pluralize(bad_count)} not set by the expected GitHub #{"app".pluralize(bad_count)}."
      end

      sig { params(unsuccessful_status_checks: T::Array[StatusCheckEvaluator::StatusCheckExpandedType]).returns(T::Hash[Symbol, T.untyped]) }
      def instrumentation_payload(unsuccessful_status_checks)
        failures = unsuccessful_status_checks.sort_by(&:context).map do |status_check|
          { status_check.context => status_check.state }
        end

        { failures_json: GitHub::JSON.encode(failures) }
      end

      def insights_ui_metadata(rule_run)
        if rule_run.evaluation_metadata.present?
          return nil unless rule_run.evaluation_metadata["check_results"]
          check_results = rule_run.evaluation_metadata["check_results"].filter do |check_result|
            check_result["checks"].any?
          end
          return nil unless check_results&.any?
          commit_map = rule_run.evaluation_metadata["commit_map"]
          integrations = Integration.where(id: check_results.map { |r| r["checks"][0]["integration_id"] }).compact.to_h { |i| [i.id, i] }

          {
            checks: check_results.map do |check_result|
              check = check_result["checks"][0]
              check_result["checks"].each do |c|
                if c["state"] != "success"
                  check = c
                  break
                end
              end
              if !check
                {}
              end
              integration = integrations[check_result["integration_id"]]

              {
                integration_name: integration ? integration.name : "",
                integration_avatar_url: integration ? integration.preferred_avatar_url : "",
                check_run_name: check_result["required"],
                id: check["id"],
                state: check["state"],
                sha: commit_map ? commit_map.key(check["commit"]) : "",
                description: additional_status_check_context(check["state"], check["duration"] ? check["duration"] : 0),
                warning: warning_map[check_result["type"].to_sym]
              }
            end
          }
        end
      end

      private

      sig { params(decision: StatusCheckEvaluator::StatusCheckRuleDecision).returns(T::Hash[Symbol, T.untyped]) }
      def create_evaluation_metadata(decision)
        # Store the commit SHAs separately to reduce stored JSON size
        commit_map = {}
        results = decision.status_check_results.map do |required, result|
          {
            required: required.context,
            integration_id: required.integration_id,
            type: result.decision_type,
            checks: result.code_by_status_check.filter_map do |check, code|
              if !check.is_a?(InMemoryRequiredStatusCheck)
                # Create a numerical ID for the commit SHA
                commit_map[check.sha] = commit_map.size unless commit_map.has_key?(check.sha)

                {
                  type: check.class,
                  id: check.id,
                  state: check.state,
                  code: code,
                  integration_id: check.integration_id,
                  commit: commit_map[check.sha],
                  duration: check.duration_in_seconds,
                }
              end
            end
          }
        end

        {
          check_results: results,
          commit_map: commit_map
        }
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          required_status_checks: T::Array[{ integration_id: Integer }],
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_valid_integrations(context, required_status_checks, errors)
        invalid_integration_ids = T.let([], T::Array[Integer])
        proposed_integration_ids = T.let([], T::Array[Integer])

        required_status_checks.each do |required_status_check|
          next if required_status_check["integration_id"].nil?

          proposed_integration_ids.push(required_status_check["integration_id"])
        end

        return errors if proposed_integration_ids.empty?

        ruleset_source = context.root["ruleset_source"]

        return errors unless ruleset_source.is_a?(Repository) || ruleset_source.is_a?(Organization)

        query = if ruleset_source.is_a?(Repository)
          IntegrationInstallation.with_repository(ruleset_source)
        else
          IntegrationInstallation.with_user(ruleset_source)
        end

        allowed_integration_ids = query.where(integration_id: proposed_integration_ids)
            .distinct
            .take(proposed_integration_ids.length)
            .pluck(:integration_id)

        allowed_integration_ids.push(*Apps::Privileged.integrations_with_access(:installed_globally, "statuses", :write).map(&:id))
        allowed_integration_ids.push(*Apps::Privileged.integrations_with_access(:installed_globally, "checks", :write).map(&:id))

        invalid_integration_ids = proposed_integration_ids - allowed_integration_ids.uniq

        return errors if invalid_integration_ids.empty?

        errors << {
          error_code: :invalid_integration_ids,
          message: "Invalid integration ids",
          value: invalid_integration_ids
        }
      end

      sig { params(context: RuleEvaluationContext, unsuccessful_status_checks: T::Array[StatusCheckEvaluator::StatusCheckExpandedType]).returns(T.nilable(String)) }
      def determine_rejection_basis_commit_sha(context, unsuccessful_status_checks)
        unsuccessful_status_checks.map do |status_check|
          if T.unsafe(status_check).respond_to?(:commit_oid)
            T.unsafe(status_check).try(:commit_oid)
          end
        end.compact.uniq.first
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        def required_status_checks_enabled?
          configs_by_type("required_status_checks").any?
        end

        def required_status_checks
          in_memory_checks = configs_by_type("required_status_checks").map do |config|
            InMemoryRequiredStatusCheck.normalize_status_checks(config, config.param("required_status_checks"))
          end.flatten

          unique(in_memory_checks)
        end

        # Needed for compat with legacy API
        def required_status_checks_enforcement_level
          return "off" unless required_status_checks_enabled?

          admin_override = configs_by_type("required_status_checks").all? do |c|
            c.source.is_a?(ProtectedBranch) && c.source.pull_request_reviews_enforcement_level != "everyone"
          end
          admin_override ? "non_admins" : "everyone"
        end

        def required_status_checks_enforced_for?(actor:)
          configs = configs_by_type("required_status_checks")
          return false unless configs.any?

          configs.any? { |config| !config.can_bypass?(actor, targetable) }
        end

        sig { returns(Promise[T::Array[InMemoryRequiredStatusCheck]]) }
        def async_required_status_checks
          return Promise.resolve(T.cast([], T::Array[InMemoryRequiredStatusCheck])) unless required_status_checks_enabled?

          configs = configs_by_type("required_status_checks")
          async_associations = configs.map { |c| c.param("async_required_status_checks")&.then { |checks| [c, checks] } }.compact
          in_memory_checks = configs.map { |c| [c, c.param("required_status_checks")] }.filter_map do |config, checks|
            checks.is_a?(Array) ? InMemoryRequiredStatusCheck.normalize_status_checks(config, checks) : nil
          end.flatten

          Promise.all(async_associations).then do |checks_by_config|
            pb_checks = checks_by_config.flat_map do |config, checks|
              InMemoryRequiredStatusCheck.normalize_status_checks(config, checks)
            end

            unique(pb_checks + in_memory_checks)
          end
        end

        def strict_required_status_checks_policy?
          configs_by_type("required_status_checks").any? { |c| c.param("strict_required_status_checks_policy") }
        end

        # Public: Does this protected branch require this context?
        #
        # context - String name of a context
        #
        # Returns Boolean
        def has_required_status_check?(context)
          async_has_required_status_check?(context).sync
        end

        def async_has_required_status_check?(context)
          return false unless required_status_checks_enabled?

          async_required_status_checks.then do |checks|
            checks.map(&:context).to_a.include?(context)
          end
        end

        # Public: Combine the current statuses passed with those that are expected for this branch. If
        # an expected status's context is found in the current statuses, remove the expected status from the list
        #
        # current_statuses - The list of statuses already reported for this branch
        #
        # Returns an Array of Statuses
        sig do
          # Using a generic parameter allows us to avoid specifying the
          # input type precisely (which is tricky, because there are many
          # classes that quack like a `Status` and could be passed in here)
          # without losing whatever type information the caller had, e.g.
          #
          #     T::Array[Foo] -> T::Array[T.any(Foo, InMemoryRequiredStatusCheck)]
          #     T::Array[T.any(Foo, Bar)] -> T::Array[T.any(Foo, Bar, InMemoryRequiredStatusCheck)]
          type_parameters(:Status)
            .params(current_statuses: T::Array[T.type_parameter(:Status)])
            .returns(T::Array[T.any(T.type_parameter(:Status), InMemoryRequiredStatusCheck)])
        end
        def current_statuses_with_expected(current_statuses)
          return current_statuses unless required_status_checks_enabled?

          contexts = Set.new(current_statuses.map { T.unsafe(_1).context })
          expected_statuses = required_status_checks.to_a

          expected_statuses.reject { |s| contexts.include?(s.context) } + current_statuses
        end

        private

        def unique(required_status_checks)
          required_status_checks.uniq { |s| [s.context, s.integration_id] }
        end
      end
    end
  end
end
