# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    module Targetable
      extend T::Sig

      sig { overridable.returns(T.nilable(Organization)) }
      def organization
        nil
      end

      sig { overridable.returns(T.nilable(Repository)) }
      def repository
        nil
      end

      sig { overridable.returns(T.nilable(String)) }
      def ref_name
        nil
      end
    end
  end
end
