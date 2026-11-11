# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RuleConditionBase
    extend T::Helpers
    extend ActiveSupport::Concern
    include IRuleCondition

    requires_ancestor { ActiveRecord::Base }

    abstract!

    included do
      T.bind(self, T.all(ClassMethods, T.class_of(ApplicationRecord::Base)))

      belongs_to impl_payload.ruleset_association_name.to_sym, class_name: impl_payload.ruleset_class
      validates impl_payload.ruleset_association_name.to_sym, presence: true
    end

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
