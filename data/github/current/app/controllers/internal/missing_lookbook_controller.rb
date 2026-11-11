# typed: true
# frozen_string_literal: true

class Internal::MissingLookbookController < ApplicationController

  def index
    # This controller is only loaded in dev, but just in case...
    return head :not_found unless Rails.env.development?

    render "internal/missing_lookbook/index", layout: false
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable = :no
  def external_conditional_access_policy_enforceable = :no
  def require_active_external_identity_session? = false
  def two_factor_enforceable = :no
  def emu_ownership_enforceable = :no
end
