# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class RepositoryPush < RulesetDefinition
    include TargetPush
    include SourceRepository

    sig { params(targets: T.nilable(T::Array[String])).returns(T::Boolean) }
    def applies_to_targets?(targets)
      super && ruleset_feature_enabled?
    end

    sig { returns(T::Boolean) }
    def ruleset_feature_enabled?
      @source.push_rulesets_enabled?
    end

    sig { returns(T::Boolean) }
    def supports_delegated_bypass?
      @source.delegated_bypass_enabled?
    end

    sig { returns(T::Boolean) }
    def is_valid?
      super &&
      # push rules are only supported when they are defined on org-owned repos that are private, and the network root
      # push rules that are defined elsewhere should be ignored
      repo.private? && !repo.fork? && self.organization.present?
    end

    sig { returns(T::Array[String]) }
    def validation_errors
      errors = []
      errors << "public repos cannot have push rules" if repo.public?
      errors << "forked repos cannot have push rules" if repo.fork?
      errors << "only org-owned repos can have push rules" unless repo.owner.is_a?(Organization)
      errors
    end

    sig { params(source: T.untyped, targets: T.nilable(T::Array[String])).returns(T::Array[RepositoryRuleset]) }
    def self.network_rulesets(source:, targets:)
      # targets must include "push" or be nil (ie, all targets)
      return [] unless targets.nil? || targets.include?("push")

      # source must be a private forked repo
      return [] unless source.is_a?(Repository) &&
      source.fork? &&
      source.private? &&
      source.network&.root_id &&
      source.network&.root_id != source.id

      repo = T.let(source, Repository)
      # recursively load the push rules of the network root
      # the async_root.sync call and the prefill_associations are a way to bypass N+1 checks in GraphQL
      root_repo = T.must(repo.network).async_root.sync
      GitHub::PrefillAssociations.prefill_associations([root_repo], [:owner, :organization])
      network_rulesets = RepositoryRuleset.load_for(source: root_repo, include_parents: true, targets: ["push"])
      network_rulesets.each { |ruleset| ruleset.inherited_from_network = true }
      network_rulesets
    end
  end
end
