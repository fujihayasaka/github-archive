# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RulesetBase
    extend T::Helpers
    extend ActiveSupport::Concern
    include IRuleset

    requires_ancestor { ActiveRecord::Base }

    abstract!

    included do
      T.bind(self, T.all(ClassMethods, T.class_of(ApplicationRecord::Base)))

      belongs_to :source, polymorphic: true

      has_many :conditions, class_name: impl_payload.rule_condition_class
      destroy_dependents_in_background :conditions

      has_many :rule_configurations, class_name: impl_payload.rule_configuration_class, inverse_of: impl_payload.ruleset_association_name.to_sym
      destroy_dependents_in_background :rule_configurations

      if impl_payload.ruleset_bypass_actor_class.present?
        has_many :bypass_actors, class_name: impl_payload.ruleset_bypass_actor_class, autosave: true
        destroy_dependents_in_background :bypass_actors
      end

      has_many :histories, -> { order("created_at DESC") }, class_name: impl_payload.ruleset_history_class
      destroy_dependents_in_background :histories
    end

    sig { abstract.returns(T.all(ActiveRecord::Associations::CollectionProxy, T::Enumerable[RuleConditionBase])) }
    def conditions; end

    sig { abstract.returns(T.all(ActiveRecord::Associations::CollectionProxy, T::Enumerable[RuleConfigurationBase])) }
    def rule_configurations; end

    #sig { abstract.returns(T.all(ActiveRecord::Associations::CollectionProxy, T::Enumerable[RulesetBypassActorBase])) }
    #def bypass_actors; end

    sig { abstract.returns(T.all(ActiveRecord::Associations::CollectionProxy, T::Enumerable[RulesetHistoryBase])) }
    def histories; end

    # TODO: Ruleset operations should all go through a domain instead of writing directly to the ActiveRecord models
    sig { abstract.params(target: String).returns(String) }
    def target=(target); end

    sig { abstract.params(source: T.untyped).returns(T.untyped) }
    def source=(source); end

    sig { abstract.params(enforcement: String).returns(String) }
    def enforcement=(enforcement); end

    module ClassMethods
      include Kernel

      sig { returns(RulesetImplementationPayload) }
      def impl_payload
        raise NotImplementedError, "Subclass must implement class method `impl_payload`"
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
