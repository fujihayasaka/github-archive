# typed: strict
# frozen_string_literal: true
#
# Trade controls screening related concern

module ApplicationController::TradeScreeningDependency
  include ResilienceHelper
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationController }

  protected

  # Public: Ensure that an actor performing a commercial interaction is screened
  # on page load.
  #
  # This is called in the before hook of a controller for a specific action that
  # renders a commercial interaction form.
  #
  # Returns nil or redirects to specified URL.
  sig { params(target: T.nilable(T.any(User, Organization, Business)), redirect_url: T.nilable(String), feature_type: Symbol, sdn_redirect: T::Boolean, blk: T.nilable(T.proc.void)).void }
  def check_actor_screening_status(target: current_user, redirect_url: nil, feature_type: :default, sdn_redirect: false, &blk)
    return unless logged_in?

    # Screen the target if they have not yet been screened
    with_database_error_fallback { target&.perform_live_sdn_screening }

    current_user_allowed = !has_commercial_interaction_restriction?(target: current_user, feature_type: feature_type)
    target_allowed = current_user_allowed && (
      target.blank? || # no need to check if no target was given
      current_user == target || # we already checked current_user
      !has_commercial_interaction_restriction?(target: target, feature_type: feature_type)
    )

    # Do nothing if the target has no restrictions
    return if target_allowed

    # at least one of current_user or target has a commercial interaction restriction
    target_with_restriction = current_user_allowed ? target : current_user
    if target_with_restriction&.show_trade_screening_flash_notice?(feature_type: feature_type)
      flash[target_with_restriction.trade_screening_status_notice] = true
    end

    yield if block_given?

    # Since we show inline warning texts for restricted status, we return here unless we force the redirect.
    return unless sdn_redirect

    sdn_suspended_entity = !target&.user? && target_with_restriction.sdn_suspended?
    if sdn_suspended_entity
      flash[:trade_screening_generic_notice] = true
    else
      flash[target_with_restriction.trade_screening_status_notice] = true
    end

    return if performed?
    return redirect_to(redirect_url) if redirect_url
    return redirect_to(org_root_path(target)) if target&.organization?
    return redirect_to(settings_billing_enterprise_path) if target.is_a?(Business)
    redirect_to(billing_url)
  rescue TradeScreeningDatabaseError
    flash[:trade_screening_unknown_error] = true
    yield if block_given?
    return redirect_to(redirect_url) if redirect_url && !performed?
    redirect_to(billing_url) unless performed?
  end

  class TradeScreeningDatabaseError < StandardError; end

  sig { params(target: T.nilable(T.any(User, Organization, Business)), feature_type: Symbol).returns(T::Boolean) }
  def has_commercial_interaction_restriction?(target:, feature_type: :default)
    result = with_database_error_fallback(fallback: :unknown) { target&.has_commercial_interaction_restriction?(feature_type: feature_type) }
    raise TradeScreeningDatabaseError if result == :unknown
    T.cast(result, T::Boolean)
  end
end
