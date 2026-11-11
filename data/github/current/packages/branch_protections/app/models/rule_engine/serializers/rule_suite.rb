# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Serializers
    module RuleSuite
      extend T::Helpers

      requires_ancestor { RuleEngine::RuleSuite }

      # Result values for Cosmos documents (reduced granularity as per schema spec)
      # Using integers for space efficiency
      # Higher value = worse result
      COSMOS_RESULT_PASS = 0
      COSMOS_RESULT_BYPASS = 1
      COSMOS_RESULT_FAIL = 2

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_rules_insights_dashboard_doc
        {
          suite_id: id,
          type: "insights",

          # Hierarchical partition key
          # Use 0 as sentinel for null business_id or org_id (Cosmos requires values for all partition key levels)
          business_id: business_id || 0,
          org_id: owner_id || 0,
          repo_id: repository_id,

          actor_id: actor_id,
          actor_type: actor_type,

          ref: ref_name,
          after_sha: after_oid,
          suite_result: result_to_cosmos_enum(result),
          created_at: created_at&.iso8601,
          created_date: created_at&.to_date&.iso8601,

          # Results per source level and evaluation mode (null = source didn't participate)
          # Active mode results
          result_active_repo: compute_source_result(Repository, :active),
          result_active_org: compute_source_result(Organization, :active),
          result_active_ent: compute_source_result(Business, :active),
          # Evaluate mode results
          result_evaluate_repo: compute_source_result(Repository, :evaluate),
          result_evaluate_org: compute_source_result(Organization, :evaluate),
          result_evaluate_ent: compute_source_result(Business, :evaluate),
          # All mode results (worst of active and evaluate)
          result_all_repo: compute_source_result(Repository, :all),
          result_all_org: compute_source_result(Organization, :all),
          result_all_ent: compute_source_result(Business, :all),

          ruleset_ids: compute_ruleset_ids,
        }
      end

      private

      sig { params(source_class: T::Class[T.anything], mode: Symbol).returns(T.nilable(Integer)) }
      def compute_source_result(source_class, mode)
        raise ArgumentError, "Invalid mode: #{mode}" unless [:active, :evaluate, :all].include?(mode)

        source_result = source_results.find { |sr| sr.source.is_a?(source_class) }

        case mode
        when :active
          # Rule suite result if source participated (i.e. has active rules), else nil
          # result: failed
          # repo_source.result: pass   -> result_active_repo: failed
          # org_source.result: failed  -> result_active_org: failed
          # ent_source.result: nil     -> result_active_ent: nil

          active_source_result = result_to_cosmos_enum(source_result&.result)
          suite_result = result_to_cosmos_enum(result)

          active_source_result.nil? ? nil : suite_result
        when :evaluate
          # result: failed
          # repo_source.evaluate_result: pass   -> result_evaluate_repo: pass
          # org_source.evaluate_result: failed  -> result_evaluate_org: failed
          # ent_source.evaluate_result: nil     -> result_evaluate_ent: nil

          result_to_cosmos_enum(source_result&.evaluate_result)
        when :all
          # What the result would have been if source evaluate result was applied.
          # Nil if no active or evaluate result for the source (i.e. source didn't participate)

          # result: pass
          # repo_source {result: nil, evaluate_result: bypass}   -> result_all_repo: bypass
          # org_source {result: pass, evaluate_result: failed}   -> result_all_org: failed
          # ent_source {result: nil, evaluate_result: nil}       -> result_all_ent: nil

          suite_result = result_to_cosmos_enum(result)

          active_source_result = result_to_cosmos_enum(source_result&.result)
          evaluate_result = result_to_cosmos_enum(source_result&.evaluate_result)
          resolved_source_result = resolve_result(active_source_result, evaluate_result)

          resolved_source_result.nil? ? nil : resolve_result(suite_result, resolved_source_result)
        end
      end

      # Maps source_result.evaluate_result enum to Cosmos values
      # Evaluate results: allowed, failed, bypassed, none
      sig { params(result: T.nilable(String)).returns(T.nilable(Integer)) }
      def result_to_cosmos_enum(result)
        case result
        when "allowed"
          COSMOS_RESULT_PASS
        when "failed"
          COSMOS_RESULT_FAIL
        when "bypassed"
          COSMOS_RESULT_BYPASS
        else
          nil
        end
      end

      # Computes the aggregated result
      # Priority: fail > bypass > pass
      sig { params(result_a: T.nilable(Integer), result_b: T.nilable(Integer)).returns(T.nilable(Integer)) }
      def resolve_result(result_a, result_b)
        return result_b if result_a.nil?
        return result_a if result_b.nil?

        [result_a, result_b].max
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
