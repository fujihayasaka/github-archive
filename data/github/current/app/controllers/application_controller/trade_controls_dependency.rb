# typed: strict
# frozen_string_literal: true

#
# Trade controls restrictions related concern

module ApplicationController::TradeControlsDependency
  extend T::Helpers

  requires_ancestor { ApplicationController }

  protected

  # Internal: used for organization settings checks
  #
  # Will check if the current_organization is trade controls restricted, and default to
  # the org messaging if so. If the org is not restricted, but
  # the current_user is trade restricted, then we use the user account messaging.
  #
  # Returns early if an organization is not in context, as we're only interested in
  # organization settings with this check. Additionally, we allow "partial" trade
  # controls restricted orgs to access their settings page.
  sig { void }
  def ensure_trade_restrictions_allows_org_settings_access
    return unless target_org

    restricted = if T.must(target_org).sdn_suspended?
      flash[:trade_controls_organization_sdn_billing_error] = true
      true
    elsif T.must(target_org).has_full_trade_restrictions?
      flash[:trade_controls_organization_billing_error] = true
      true
    elsif current_user&.has_any_trade_restrictions? && T.must(target_org).charged_account?
      flash[:trade_controls_user_billing_error] = true
      true
    end

    redirect_to(org_root_path(target_org)) if restricted
  end

  sig { params(fallback_location: String).void }
  def ensure_trade_restrictions_allows_org_member_management(fallback_location:)
    return unless target_org

    if T.must(target_org).has_full_trade_restrictions?
      flash[:trade_controls_organization_billing_error] = true
      redirect_back(fallback_location: fallback_location)
    end
  end

  private

  sig { returns(T.nilable(Organization)) }
  def target_org
    @target_org ||= T.let(
      if defined?(T.unsafe(self).this_organization)
        T.unsafe(self).this_organization
      else
        T.unsafe(self).current_organization
      end, T.nilable(Organization))
  end
end
