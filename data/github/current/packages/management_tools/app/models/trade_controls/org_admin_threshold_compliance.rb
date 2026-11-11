# typed: strict
# frozen_string_literal: true

module TradeControls
  class OrgAdminThresholdCompliance
    BATCH_SIZE = 1000

    include Compliance

    sig { params(organization: Organization, kwargs: T.untyped).void }
    def initialize(organization:, **kwargs)
      @organization = organization
      @admin_ids = T.let(@organization.admin_ids, T::Array[String])
      @reason = T.let(:organization_admin, Symbol)
    end

    sig { override.returns(Organization) }
    def organization
      @organization
    end

    sig { override.returns(T.any(String, Symbol)) }
    def reason
      @reason
    end

    sig { returns(Integer) }
    def admins_count
      @admins_count ||= T.let(@admin_ids.size, T.nilable(Integer))
    end

    sig { returns(Integer) }
    def trade_restricted_admins_count
      @trade_restricted_admins_count ||= T.let(TradeControls::Restriction.any_restricted_ids(@admin_ids).count, T.nilable(Integer))
    end

    sig { returns(T.any(Integer, Float)) }
    def current_threshold
      return 0 if admins_count.zero? || trade_restricted_admins_count.zero?

      @current_threshold ||= T.let(((trade_restricted_admins_count.to_f / admins_count) * 100).round(2), T.nilable(T.any(Integer, Float)))
    end

    sig { override.returns(T::Boolean) }
    def violation?
      full_restriction_violation? || tier_0_restriction_violation? || tier_1_restriction_violation?
    end

    sig { override.returns(T::Boolean) }
    def full_restriction_violation?
      current_threshold >= 50 && organization.charged_account?
    end

    sig { override.returns(T::Boolean) }
    def tier_1_restriction_violation?
      current_threshold >= 50 && organization.uncharged_account?
    end

    sig { override.returns(T::Boolean) }
    def tier_0_restriction_violation?
      current_threshold.between?(25.00, 49.99) && organization.uncharged_account?
    end

    sig { override.returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def to_hydro
      {
        reason: reason,
        percentage_of_trade_restricted_admins: current_threshold,
      }
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { override.params(kwargs: T.untyped).returns(T.untyped) }
    def event_context(**kwargs)
      Context::Expander.expand(org_admin_threshold: current_threshold, reason: reason)
    end
  end
end
