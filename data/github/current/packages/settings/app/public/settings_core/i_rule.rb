# typed: strict
# frozen_string_literal: true

module SettingsCore
  module IRule
    extend T::Helpers
    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(ISetting)) }
    def setting; end

    sig { abstract.returns(String) }
    def rule_type; end

    sig { abstract.returns(T::Hash[String, T.untyped]) }
    def parameters; end

    sig { abstract.returns(IConditionExpression) }
    def condition_expression; end

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end
  end
end
