# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Strategies
    class CommitMetadataStrategy < RuleEvaluationStrategy
      extend T::Sig
      extend T::Helpers
      include RuleEngine::Timing

      METADATA_TYPES = T.let([:blob, :commit, :ref], T::Array[Symbol])

      sig { void }
      def initialize
        super(processes_type: CommitRule)
      end

      sig do
        override.params(
          event: RuleEvent,
          rule_configs_and_impl: T::Array[[RepositoryRuleConfiguration, BaseRule]],
        ).returns(T::Array[RuleEngine::RuleRun])
      end
      def process_rules(event, rule_configs_and_impl)
        return [] unless event.is_a?(GitEvent)

        # Store each config by ref update partitioned by its type then by metadata type
        metadata_type_commit_rules_by_ref_update = T.let(
          Hash.new { |a, b| a[b] = Hash.new { |c, d| c[d] = Hash.new { |e, f| e[f] = [] } }  },
          T::Hash[Git::Ref::Update, T::Hash[Symbol, T::Hash[String, T::Array[RepositoryRuleConfiguration]]]]
        )

        event.event_actions.each do |ref_update|
          rule_configs_and_impl.each do |rule_config, rule_impl|
            next unless rule_impl.is_a?(CommitRule)
            next unless rule_config.provider_rule_matches_ref?(ref_update.refname)

            METADATA_TYPES.each do |metadata_type|
              next unless rule_impl.supported_metadata_types.include?(metadata_type)

              # Uses the implementation name to handle companion rules which have different names
              T.must(T.must(T.must(metadata_type_commit_rules_by_ref_update[ref_update])[metadata_type])[rule_impl.rule_name]) << rule_config
            end
          end
        end

        # Commit rules are evaluated multiple times, so this hash keeps track of the total execution time
        timings_by_commit_rule_name = Hash.new { |h, k| h[k] = 0 }

        # To reduce memory pressure, we run rules on each page returned in the various datasets
        all_rule_runs = metadata_type_commit_rules_by_ref_update.flat_map do |ref_update, commit_rules_by_metadata_type|
          commit_rules_by_metadata_type.flat_map do |metadata_type, rule_configs_by_rule_type|
            trace_time("commit_rule_evaluation", tags: ["metadata_type:#{metadata_type}"], span_attributes: { "gh.branch_protection_rule.metadata_type" => metadata_type.to_s }) do |span|
              self.evaluate_commit_rules_for_metadata_type(
                span,
                event,
                metadata_type,
                rule_configs_by_rule_type,
                timings_by_commit_rule_name,
                ref_update
              )
            end
          end
        end

        # Publish all of the generated timings to DataDog
        if timings_by_commit_rule_name.any?
          timings_by_commit_rule_name.each do |rule_name, elapsed|
            GitHub.dogstats.distribution("repository_rules_engine.rule_evaluation.duration", elapsed, tags: ["type:#{rule_name}", "eval_type:commit"])
          end
        end

        all_rule_runs
      end

      sig do
        params(
          tracer_span: T.untyped,
          event: GitEvent,
          type: Symbol,
          rule_configs_by_type: T::Hash[String, T::Array[RepositoryRuleConfiguration]],
          timings_by_rule_name: T::Hash[String, Float],
          ref_update: Git::Ref::Update
        ).returns(T::Array[RuleRun])
      end
      private def evaluate_commit_rules_for_metadata_type(
        tracer_span,
        event,
        type,
        rule_configs_by_type,
        timings_by_rule_name,
        ref_update)
        return [] if rule_configs_by_type.empty?

        cursor = T.let(nil, T.untyped)
        type_result_total = 0
        has_metadata_source = T.let(true, T::Boolean)
        metadata_source_total_duration = T.let(0, T.any(Float, Integer))

        rule_impl_violations_by_rule_config = T.let(
          Hash.new,
          T::Hash[RepositoryRuleConfiguration, T::Hash[RuleEngine::CommitRule, T::Array[Violation]]]
        )

        legacy_context = event.legacy_evaluation_context

        loop do
          type_result = nil

          start = Time.now

          case type
          when :blob
            collection = event.blobs(ref_update, cursor)
            cursor = collection.next_cursor
            type_result = collection.items
          when :commit
            collection = event.commits(ref_update, cursor)
            cursor = collection.next_cursor
            type_result = collection.items
          when :ref
            has_metadata_source = false
            type_result = [ref_update]
          else
            raise NotImplementedError, "Unsupported type #{type}"
          end

          elapsed = (Time.now - start) * 1000
          metadata_source_total_duration += elapsed

          rule_configs_by_type.each do |rule_type, rule_configs|
            start = Time.now

            rule_impl = T.cast(T.must(GenericEvaluator.rule_impl_for_rule_type(rule_type)), RuleEngine::CommitRule)

            rule_impl.bulk_evaluate_candidates(legacy_context, ref_update, rule_configs, type_result).each do |config, results|
              results.each do |result|
                rule_impl_violations_by_rule_config[config] ||= { rule_impl => [] }
                T.must(T.must(rule_impl_violations_by_rule_config[config])[rule_impl]).push(Violation.from_evaluation_result(result)) unless result.success?
              end
            end

            elapsed = (Time.now - start) * 1000
            timings_by_rule_name[rule_impl.rule_name] = T.must(timings_by_rule_name[rule_impl.rule_name]) + elapsed
          end

          type_result_total += type_result.size

          break if cursor.nil?
        end

        rule_runs = rule_configs_by_type.flat_map do |rule_type, rule_configs|
          start = Time.now

          rule_impl = T.cast(T.must(GenericEvaluator.rule_impl_for_rule_type(rule_type)), RuleEngine::CommitRule)

          rule_configs.map do |rule_config|
            violations = if rule_impl_violations_by_rule_config.key?(rule_config) && T.must(rule_impl_violations_by_rule_config[rule_config]).key?(rule_impl)
              T.must(T.must(rule_impl_violations_by_rule_config[rule_config])[rule_impl])
            else
              []
            end

            rule_run = rule_impl.generate_evaluation_result(legacy_context, ref_update, rule_config, violations)

            elapsed = (Time.now - start) * 1000
            timings_by_rule_name[rule_impl.rule_name] = T.must(timings_by_rule_name[rule_impl.rule_name]) + elapsed

            rule_run
          end
        end

        GitHub.dogstats.count("repository_rules_engine.metadata.processed", type_result_total, tags: ["type:#{type}"])
        tracer_span&.set_attribute("gh.branch_protection_rule.metadata.processed", type_result_total)

        if has_metadata_source
          GitHub.dogstats.distribution("repository_rules_engine.metadata.source.duration", metadata_source_total_duration, tags: ["source:#{event.metadata_source_name}", "metadata_type:#{type}"])
          tracer_span&.set_attribute("gh.branch_protection_rule.metadata.source.duration", metadata_source_total_duration)
        end

        validate_rule_runs({ ref_update => rule_configs_by_type.values.flatten }, rule_runs, event.repository)

        rule_runs
      end
    end
  end
end
