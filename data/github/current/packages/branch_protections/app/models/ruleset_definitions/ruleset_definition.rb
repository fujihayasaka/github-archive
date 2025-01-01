# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class RulesetDefinition

    def self.factory(source, source_type, target)
      if source
        # use source_type instead of source because source may have been destroyed when we get here
        source_type = source.class.name
      end

      if source.is_a?(Organization) || source_type == "User" || source_type == "Organization"
        return OrganizationBranch.new(source, target) if target == "branch"
        return OrganizationTag.new(source, target) if target == "tag"
        return OrganizationPush.new(source, target) if target == "push"
        return OrganizationRepository.new(source, target) if target == "repository"
      elsif source.is_a?(Repository) || source_type == "Repository"
        return RepositoryBranch.new(source, target) if target == "branch"
        return RepositoryTag.new(source, target) if target == "tag"
        return RepositoryPush.new(source, target) if target == "push"
      elsif source.is_a?(Business) || source_type == "Business"
        return BusinessBranch.new(source, target) if target == "branch"
        return BusinessTag.new(source, target) if target == "tag"
        return BusinessPush.new(source, target) if target == "push"
        return BusinessRepository.new(source, target) if target == "repository"
      else
        raise RepositoryRuleset::InvalidSource.new(source_type)
      end

      raise RepositoryRuleset::InvalidTarget.new(target)
    end

    def initialize(source, target)
      @source = source
      @target = target
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def plan_supports?(feature)
      @source.plan_supports?(feature)
    end

    sig { returns(T::Boolean) }
    def ruleset_feature_enabled?
      true
    end

    sig { returns(T::Boolean) }
    def supports_delegated_bypass?
      true
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      raise NotImplementedError.new("url must be implemented by the subclass")
    end

    sig { returns(String) }
    def edit_index_url
      raise NotImplementedError.new("edit_index_url must be implemented by the subclass")
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      raise NotImplementedError.new("edit_url must be implemented by the subclass")
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      raise NotImplementedError.new("history_url must be implemented by the subclass")
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def event_payload
      {}
    end

    sig { params(targets: T::nilable(T::Array[String])).returns(T::Boolean) }
    def applies_to_targets?(targets)
      (targets.nil? || targets.empty? || targets.include?(@target))
    end

    # determines if this ruleset is valid, or if it should be ignored
    # we ignore rulesets if the source has the wrong paid plan,
    # or the source is not supported (like push rules on a public repo)
    sig { returns(T::Boolean) }
    def is_valid?
      is_valid_for_source?
    end

    # this is overridden by the subclass modules
    sig { returns(T::Boolean) }
    def is_valid_for_source?
      false
    end

    sig { returns(T::Array[String]) }
    def validation_errors
      []
    end

    sig do
      params(targetable: RuleEngine::Conditions::Targetable)
      .returns(RuleEngine::Conditions::Targetable)
    end
    def redirect_condition_targetable(targetable)
      # by default, don't change anything
      targetable
    end

    # Whether a ruleset target supports a specific targetable object
    sig { params(targetable: RuleEngine::Conditions::Targetable).returns(T::Boolean) }
    def target_supports_targetable?(targetable)
      true
    end

    sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def required_condition_targets
      source_required_condition_targets + target_required_condition_targets
    end

    sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def source_required_condition_targets
      raise NotImplementedError.new("source_required_condition_targets must be implemented by subclasses")
    end

    sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def target_required_condition_targets
      raise NotImplementedError.new("target_required_condition_targets must be implemented by subclasses")
    end

    sig { returns(String) }
    def display_type
      raise NotImplementedError.new("display_type must be implemented by subclasses")
    end

    sig { returns(String) }
    def display_source_name
      raise NotImplementedError.new("display_source_name must be implemented by subclasses")
    end

    sig { params(ruleset: RepositoryRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      raise NotImplementedError.new("applies_to_source? must be implemented by subclasses")
    end

    sig { returns(T::Boolean) }
    def supports_evaluate_mode?
      raise NotImplementedError.new("supports_evaluate_mode? must be implemented by subclasses")
    end

    # if I define a signature like:
    # sig { void }
    # then this method returns T::Private::Types::Void::VOID
    # which breaks the science experiment
    def reconcile_merge_queues
    end
  end
end
