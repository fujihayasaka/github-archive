# typed: strict
# frozen_string_literal: true

module Growth
  class TradeScreeningCannotProceedComponent < ApplicationComponent
    extend T::Sig

    sig { returns(T.untyped) }
    attr_reader :system_arguments

    sig { params(target: T.any(User, Organization, Business), check_for_current_user: T::Boolean, system_arguments: T.untyped).void }
    def initialize(target:, check_for_current_user:, **system_arguments)
      @target = target
      @check_for_current_user = check_for_current_user
      @system_arguments = system_arguments
    end

    sig { returns(T::Boolean) }
    def render?
      trade_screening_error_data.present?
    end

    private

    sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
    memoize def trade_screening_error_data
      helpers.trade_screening_cannot_proceed_error_data(target: @target, check_for_current_user: @check_for_current_user)
    end
  end
end
