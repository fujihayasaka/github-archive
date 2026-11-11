# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class RepositoryPush < RulesetDefinition
    include TargetPush
    include SourceRepository

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

    sig { params(ruleset: RuleEngine::IRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      redirected_object = object.is_a?(Repository) && object.fork? && (root = object.network&.root) ? root : object
      # Legacy compat: we don't allow creating push rulesets on forks but the previous implementation allowed loading them (but not evaluating them)
      # match this behavior for now by also checking the original object
      super(ruleset, redirected_object) || super(ruleset, object)
    end

    sig { params(viewing_source: T.untyped).returns(String) }
    def display_type(viewing_source: nil)
      return "Upstream" if viewing_source.is_a?(Repository) && viewing_source.fork? && viewing_source.private?
      super
    end
  end
end
