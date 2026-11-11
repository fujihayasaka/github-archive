# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class NonFastForwardRule < RefUpdateRule

      def initialize
        super(rule_name: "non_fast_forward",
              display_name: "Block force pushes",
              description: "Prevent users with push access from force pushing to refs.")
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
        [:creation, :deletion]
      end

      # The non-fast-forward policy has no configuration: return the same result for each configuration
      sig { override.params(context: RuleEvaluationContext, policies_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def bulk_evaluate(context, policies_by_ref_update)
        repository = context.repository
        ref_updates = policies_by_ref_update.keys

        ref_updates_requiring_descendants_check = ref_updates.select { |ref_update| ref_update.fast_forward.nil? }

        if ref_updates_requiring_descendants_check.any?
          updates_by_commit_and_ancestor = ref_updates_requiring_descendants_check.group_by do |ref_update|
            [ref_update.after_oid, ref_update.before_oid]
          end
          repository.rpc.descendant_of(updates_by_commit_and_ancestor.keys).each do |commit_and_ancestor, is_descendant|
            updates_by_commit_and_ancestor[commit_and_ancestor]&.each do |ref_update|
              ref_update.fast_forward = is_descendant
            end
          end
        end

        policies_by_ref_update.flat_map do |ref_update, rule_configs|
          if ref_update.fast_forward
            rule_configs.map { |rule_config| RuleRun.success(rule_config:, ref_update:) }
          else
            rule_configs.map do |rule_config|
              RuleRun.failure(rule_config:, ref_update:, message: "Cannot force-push to this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}")
            end
          end
        end
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        def block_force_pushes_enabled?
          configs_by_type("non_fast_forward").any?
        end
      end
    end
  end
end
