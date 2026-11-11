# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RulesetHistoryBase
    extend T::Helpers
    extend ActiveSupport::Concern

    included do
      T.bind(self, T.all(ClassMethods, T.class_of(ApplicationRecord::Base)))

      belongs_to impl_payload.ruleset_association_name.to_sym, class_name: impl_payload.ruleset_class

      belongs_to :updated_by, class_name: "User"

      validates impl_payload.ruleset_association_name.to_sym, presence: true
      validates :state, presence: true
      validates :updated_by_id, presence: true
    end

    abstract!

    sig { abstract.returns(T.untyped) }
    def state; end

    sig { abstract.returns(IRuleset) }
    def ruleset_from_state; end

    # Returns the history's state as a hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def deserialized
      @deserialized ||= T.let(
        state.blank? ? {} : JSON.parse(state, symbolize_names: true),
        T.nilable(T::Hash[Symbol, T.untyped])
      )
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
