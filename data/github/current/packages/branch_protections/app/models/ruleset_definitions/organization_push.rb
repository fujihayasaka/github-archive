# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationPush < RulesetDefinition
    include TargetPush
    include SourceOrganization

    sig { params(ruleset: RuleEngine::IRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      object = object.is_a?(Repository) && object.fork? && (root = object.network&.root) ? root : object
      if super(ruleset, object)
        object.is_a?(Organization) ||
        RulesetDefinitions::RulesetDefinition.factory(object, "Repository", "push").is_valid?
      else
        false
      end
    end

    sig { params(viewing_source: T.untyped).returns(String) }
    def display_type(viewing_source: nil)
      return "Upstream" if viewing_source.is_a?(Repository) && viewing_source.fork? && viewing_source.private?
      super
    end
  end
end
