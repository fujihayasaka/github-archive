# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    module Targetable

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

      sig { overridable.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def repo_create_custom_properties
        nil
      end
    end
  end
end
