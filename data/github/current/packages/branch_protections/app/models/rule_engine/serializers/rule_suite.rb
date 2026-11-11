# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Serializers
    module RuleSuite
      extend T::Helpers

      requires_ancestor { RuleEngine::RuleSuite }

      # Result symbols matching the Hydro proto enum names
      RESULT_NONE = :none
      RESULT_PASS = :pass
      RESULT_BYPASS = :bypass
      RESULT_FAIL = :fail

      # Priority ordering for result comparison (higher index = worse result)
      RESULT_PRIORITY = T.let([RESULT_NONE, RESULT_PASS, RESULT_BYPASS, RESULT_FAIL].freeze, T::Array[Symbol])

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_rules_insights_dashboard_doc
        {
          suite_id: id,

          # Hierarchical partition key
          # Use 0 as sentinel for null business_id or org_id (Cosmos requires values for all partition key levels)
          business_id: business_id || 0,
          org_id: owner_id || 0,
          repo_id: repository_id,

          actor_id: actor_id,
          actor_type: actor_type,

          ref: ref_name,
          after_sha: after_oid,
          suite_result: result_to_enum(result),
          created_at: created_at,
          created_date: created_at&.to_date&.iso8601,

          # Results per source level and evaluation mode (null = source didn't participate)
          # Active mode results
          result_active_repo: compute_source_result(Repository, :active),
          result_active_org: compute_source_result(Organization, :active),
          result_active_business: compute_source_result(Business, :active),
          # Evaluate mode results
          result_evaluate_repo: compute_source_result(Repository, :evaluate),
          result_evaluate_org: compute_source_result(Organization, :evaluate),
          result_evaluate_business: compute_source_result(Business, :evaluate),
          # All mode results (worst of active and evaluate)
          result_all_repo: compute_source_result(Repository, :all),
          result_all_org: compute_source_result(Organization, :all),
          result_all_business: compute_source_result(Business, :all),

          ruleset_ids: compute_ruleset_ids,
        }
      end

      private

      sig { params(source_class: T::Class[T.anything], mode: Symbol).returns(Symbol) }
      def compute_source_result(source_class, mode)
        source_result = source_results.find { |sr| sr.source.is_a?(source_class) }

        case mode
        when :active
          # Shows pushes that hit active rulesets: did they pass, get blocked, or get bypassed?
          # At org/enterprise, this only includes pushes where that org or enterprise had rulesets involved.
          # result: failed
          # repo_source.result: pass   -> result_active_repo: failed
          # org_source.result: failed  -> result_active_org: failed
          # ent_source.result: nil     -> result_active_ent: none

          active_source_result = result_to_enum(source_result&.result)
          suite_result = result_to_enum(result)

          if source_class == Repository
            any_active = source_results.any? { |sr| result_to_enum(sr.result) != RESULT_NONE }
            any_active ? suite_result : RESULT_NONE
          else
            active_source_result == RESULT_NONE ? RESULT_NONE : suite_result
          end
        when :evaluate
          # Shows how pushes fared against this source's evaluate rulesets.
          # result: failed
          # repo_source.evaluate_result: pass   -> result_evaluate_repo: pass
          # org_source.evaluate_result: failed  -> result_evaluate_org: failed
          # ent_source.evaluate_result: nil     -> result_evaluate_ent: none

          result_to_enum(source_result&.evaluate_result)
        when :all
          # Shows what would have happened if this source's evaluate rulesets were also active.
          # At org/enterprise, this only includes pushes where that org or enterprise had rulesets involved.
          # result: pass
          # repo_source {result: nil, evaluate_result: bypass}   -> result_all_repo: bypass
          # org_source {result: pass, evaluate_result: failed}   -> result_all_org: failed
          # ent_source {result: nil, evaluate_result: nil}       -> result_all_ent: none

          suite_result = result_to_enum(result)

          active_source_result = result_to_enum(source_result&.result)
          evaluate_result = result_to_enum(source_result&.evaluate_result)
          resolved_source_result = resolve_result(active_source_result, evaluate_result)

          if source_class == Repository
            any_active = source_results.any? { |sr| result_to_enum(sr.result) != RESULT_NONE }
            (any_active || !source_result.nil?) ? resolve_result(suite_result, resolved_source_result) : RESULT_NONE
          else
            resolved_source_result == RESULT_NONE ? RESULT_NONE : resolve_result(suite_result, resolved_source_result)
          end
        else
          raise ArgumentError, "Invalid mode: #{mode}"
        end
      end

      # Maps result enum values to standardized symbols
      # RuleSuite results: allowed, failed, git_error, bypassed, push_rejected, entered_queue, enter_queue_failed
      # RuleSuiteSourceResult results: allowed, failed, bypassed
      sig { params(result: T.nilable(String)).returns(Symbol) }
      def result_to_enum(result)
        case result
        when "allowed"
          RESULT_PASS
        when "failed", "git_error", "stack_merge_failed"
          RESULT_FAIL
        when "bypassed"
          RESULT_BYPASS
        else
          # nil, "entered_queue", "enter_queue_failed", "push_rejected", or unknown
          # - enter_queue_failed: activity page silently drops these (rule_suite_json returns nil)
          # - push_rejected: not in RESULT_MAP["fail"], so excluded from activity page fail filter
          # Both are mapped to NONE so the dashboard stays consistent with the activity page.
          RESULT_NONE
        end
      end

      # Computes the aggregated result
      # Priority: fail > bypass > pass > none
      sig { params(result_a: Symbol, result_b: Symbol).returns(Symbol) }
      def resolve_result(result_a, result_b)
        priority_a = RESULT_PRIORITY.index(result_a) || 0
        priority_b = RESULT_PRIORITY.index(result_b) || 0

        T.must(RESULT_PRIORITY[[priority_a, priority_b].max])
      end

      # Extracts unique ruleset IDs from rule_runs that are backed by rulesets
      sig { returns(T::Array[Integer]) }
      def compute_ruleset_ids
        rule_runs
          .filter(&:ruleset_provider?)
          .filter_map(&:rule_provider_id)
          .uniq
          .sort
      end
    end
  end
end
