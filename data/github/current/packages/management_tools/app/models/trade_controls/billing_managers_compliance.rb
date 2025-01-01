# typed: strict
# frozen_string_literal: true

module TradeControls
  class BillingManagersCompliance
    include Compliance
    extend T::Sig

    sig { params(organization: ::Organization, kwargs: T.untyped).void }
    def initialize(organization:, **kwargs)
      @organization = organization
      @billing_manager_ids = T.let(organization.billing_manager_ids, T::Array[Integer])
      @reason = T.let(:organization_billing_manager, Symbol)
    end

    sig { override.returns(::Organization) }
    def organization
      @organization
    end

    sig { override.returns(T.any(String, Symbol)) }
    def reason
      @reason
    end

    sig { returns(Integer) }
    def number_of_billing_managers
      @number_of_billing_managers ||= T.let(@billing_manager_ids.size, T.nilable(Integer))
    end

    sig { returns(Integer) }
    def number_of_trade_restricted_billing_managers
      @number_of_trade_restricted_billing_managers ||= T.let(TradeControls::Restriction.any_restricted_ids(@billing_manager_ids).count, T.nilable(Integer))
    end

    sig { returns(T.any(Integer, Float)) }
    def current_threshold
      return 0 if number_of_billing_managers.zero? || number_of_trade_restricted_billing_managers.zero?

      @current_threshold ||= T.let(((number_of_trade_restricted_billing_managers.to_f / number_of_billing_managers) * 100).round(2), T.nilable(T.any(Integer, Float)))
    end

    sig { override.returns(T::Boolean) }
    def violation?
      full_restriction_violation? || tier_1_restriction_violation?
    end

    sig { override.returns(T::Boolean) }
    def full_restriction_violation?
      current_threshold >= 50 && organization.charged_account?
    end

    sig { override.returns(T::Boolean) }
    def tier_1_restriction_violation?
      current_threshold >= 25 && organization.uncharged_account?
    end

    sig { override.returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def to_hydro
      {
        reason: reason,
        percentage_of_trade_restricted_billing_managers: current_threshold,
      }
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { override.params(kwargs: T.untyped).returns(T.untyped) }
    def event_context(**kwargs)
      Context::Expander.expand(percentage_of_trade_restricted_billing_managers: current_threshold, reason: reason)
    end
  end
end
