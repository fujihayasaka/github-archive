# typed: true
# frozen_string_literal: true

class Marketplace::PendingInstallations::DismissalsController < ApplicationController

  before_action :login_required
  before_action :marketplace_required

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  def create
    Marketplace::PendingInstallations::Notice.new(user_id: current_user.id).dismiss

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  # Opting out from conditional access policies is handled in this method
  def external_conditional_access_policy_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end
end
