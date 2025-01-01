# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class ProtectedBranchRuleProvider < RuleProvider
      include GitRuleProvider
      include Bypasses

      def initialize
        super(identifier: "protected_branch")
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[RepositoryRuleConfiguration]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        branches = ref_updates.filter(&:branch?).map(&:refname)
        return [] if branches.empty?

        rules_for_protected_branches(repository, branches, filter_apply_on_create: true)
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        branches = ref_names.filter { |ref| ref.start_with?("refs/heads/") }
        return [] if branches.empty?

        rules_for_protected_branches(repository, branches)
      end

      sig { override.params(rule_run: RuleRun).returns(T.nilable(String)) }
      def insights_category(rule_run)
        "Branch protection"
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: Types::Actor,
          repository: Repository,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, repository, rule_run = nil)
        return false if rule_run.present? && rule_run.evaluation_metadata["bypass_prohibited"]

        if rule_config.has_param("actor_allowances")
          bypass_actors = rule_config.param("actor_allowances").to_a
          return true if allowed_bypass_modes(bypass_actors, actor, repository).include?(:any)
        end

        if bypass_level(rule_config.source, rule_config.rule_type) != "everyone"
          actor_bypass_authorized?(actor, repository) || false
        else
          false
        end
      end

      private

      def bypass_level(protected_branch, rule_type)
        case rule_type
        when "required_linear_history"
          protected_branch.linear_history_requirement_enforcement_level
        when "merge_queue"
          protected_branch.merge_queue_enforcement_level
        when "required_review_thread_resolution"
          protected_branch.required_review_thread_resolution_enforcement_level
        when "required_deployments"
          protected_branch.required_deployments_enforcement_level
        when "required_signatures"
          protected_branch.signature_requirement_enforcement_level
        when "pull_request"
          protected_branch.pull_request_reviews_enforcement_level
        when "required_status_checks"
          protected_branch.required_status_checks_enforcement_level
        when "lock_branch"
          protected_branch.lock_branch_enforcement_level
        # Deletion, authorization, and non-fast-forward policies are not overridable by admins
        when "non_fast_forward"
          "everyone"
        when "deletion"
          "everyone"
        when "authorization"
          "everyone"
        end
      end

      sig do
        params(
          repository: Repository,
          ref_names: T::Array[String],
          filter_apply_on_create: T::Boolean)
        .returns(T::Array[RepositoryRuleConfiguration])
      end
      def rules_for_protected_branches(repository, ref_names, filter_apply_on_create: false)
        return [] unless repository.supports_protected_branches?
        return [] if BranchProtectionsConfig.new(repository).branch_protection_disabled?
        protected_branches = Platform::Loaders::BranchProtectionRule::ByRepository.load(repository).sync

        all_rules = protected_branches.flat_map { |pb| pb.generate_rules(self) }

        pb_matches = ref_names.map do |ref_name|
          ordered_protected_branches = protected_branches.sort_by do |protected_branch|
            [protected_branch.wildcard_rule? ? 1 : 0, protected_branch.id]
          end

          branch = ordered_protected_branches.find do |protected_branch|
            protected_branch.matches_qualified_ref_name?(ref_name)
          end
          [ref_name, [branch]]
        end.to_h

        all_rules.each do |rule|
          rule.matching_ref_names += ref_names.filter do |ref_name|
            # Ignore rules that don't apply to branch creation
            if filter_apply_on_create && !rule.source.create_protected? && !repository.heads[ref_name].present?
              next false
            end
            pb_matches[ref_name]&.include?(rule.source)
          end
        end
      end
    end
  end
end
