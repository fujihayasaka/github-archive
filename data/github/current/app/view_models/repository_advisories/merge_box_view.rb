# typed: true
# frozen_string_literal: true

module RepositoryAdvisories
  class MergeBoxView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :advisory

    delegate :repository, :workspace_repository, :open_pull_requests,
      to: :advisory

    def admin?
      return @is_admin if defined? @is_admin
      @is_admin = advisory.adminable_by?(current_user)
    end

    def merge_state
      @merge_state ||=
        if pull_request_merge_states.empty? && unmerged_changes?
          :unmerged_changes
        elsif pull_request_merge_states.empty?
          :no_changes
        elsif batch_merge.invalid?
          :invalid
        elsif pull_request_merge_states.include?(:draft)
          :draft
        elsif pull_request_merge_states.include?(:dirty)
          :dirty
        elsif pull_request_merge_states.include?(:unknown)
          :unknown
        else
          :clean
        end
    end

    def mergeable?
      merge_state == :clean
    end

    def viewer_may_merge?
      admin? && !targeted_by_rules?
    end

    def viewer_blocked_by_rules?
      admin? && targeted_by_rules?
    end

    def viewer_can_bypass_rules?
      viewer_blocked_by_rules? && can_bypass_targeted_rules?
    end

    def viewer_can_merge?
      mergeable? && viewer_may_merge?
    end

    def open_pull_request_count
      open_pull_requests.count
    end

    def merge_box_path
      urls.advisory_workspace_merge_box_path(repository.owner, repository, advisory)
    end

    def merge_path
      urls.merge_advisory_workspace_path(repository.owner, repository, advisory)
    end

    def current_head_shas
      open_pull_requests.map(&:head_sha)
    end

    def validation_error_messages
      batch_merge.tap(&:validate).errors.full_messages
    end

    private

    def batch_merge
      @batch_merge ||= advisory.build_batch_merge(actor: current_user)
    end

    def pull_request_merge_states
      @pull_request_merge_states ||= Set.new.tap do |merge_states|
        open_pull_requests.each do |pull_request| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          merge_states << pull_request.merge_state(viewer: current_user).status
        end
      end
    end

    def unmerged_changes?
      # Only compare default branch <-> default branch
      comparison = GitHub::Comparison.deprecated_build(workspace_repository,
        "#{repository.owner.display_login}:#{repository.default_branch}",
        "#{workspace_repository.owner.display_login}:#{workspace_repository.default_branch}"
      )
      return false unless comparison.valid?

      comparison.ahead?
    end

    def rule_evaluators
      return @evaluators if defined? @evaluators

      @evaluators = if is_rule_evaluation_enabled?
        BranchRuleEvaluator.for_repository_with_branch_names(repository, open_pull_requests.map(&:base_ref)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      else
        nil
      end
    end

    sig { returns(T::Array[RepositoryRuleConfiguration]) }
    def rules
      return [] unless rule_evaluators.present?

      @enabled_rules ||= rule_evaluators
        .values
        .flat_map(&:rule_configs)
        .uniq { |rule| rule.id }
        .select { |rule| rule.enabled? && !rule.can_skip?(current_user, RuleEngine::Conditions::Targets::Repository.new(repository: repository)) }
    end

    def targeted_by_rules?
      rules.any?
    end

    def can_bypass_targeted_rules?
      return @can_bypass_rules if defined? @can_bypass_rules

      @can_bypass_rules = rules.all? do |rule|
        next true if rule.provider_name == "protected_branch"

        rule.can_bypass?(current_user, RuleEngine::Conditions::Targets::Repository.new(repository: repository))
      end
    end

    def is_rule_evaluation_enabled?
      return false if repository.async_scoped_feature_flag_enabled?(:security_advisory_rule_evaluation_opt_out).sync

      repository.async_scoped_feature_flag_enabled?(:security_advisory_rule_evaluation).sync
    end
  end
end
