# typed: strict
# frozen_string_literal: true

module Organization::TradeControlsDependency
  extend T::Sig
  extend T::Helpers
  requires_ancestor { Organization }

  sig { void }
  def send_trade_controls_enforcement_email
    TradeControlsMailer.organization_restricted(T.cast(self, Organization)).deliver_later
  end

  sig { void }
  def send_trade_controls_override_email
    TradeControlsMailer.organization_reactivated(T.cast(self, Organization)).deliver_later
  end

  sig { params(compliance: TradeControls::Compliance, kwargs: T.untyped).void }
  def instrument_trade_controls_enforcement(compliance:, **kwargs)
    InstrumentOrganizationTradeRestrictionEnforceJob.perform_later(
      **T.unsafe({ organization: self, **compliance.to_hydro, **kwargs }))
  end

  sig { returns(ActiveRecord::Relation) }
  def trade_controls_restricted_members
    TradeControls::Restriction.not_unrestricted.where(user: member_ids)
  end

  sig { void }
  def send_trade_controls_restricted_free_org_allowed_email
    TradeScreeningMailer.restricted_free_organization_allowed_status(T.cast(self, Organization)).deliver_later
  end
end
