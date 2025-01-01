# typed: strict
# frozen_string_literal: true

class ::Businesses::AdvancedSecurity::SelfServeController < ::Businesses::BusinessController
  include BillingSettingsHelper

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :ensure_self_serve_advanced_security

  protected

  sig { void }
  def ensure_self_serve_advanced_security
    render_404 unless this_business.eligible_for_self_serve_advanced_security?
  end

  sig { params(error_message: String).void }
  def respond_with_error(error_message)
    respond_to do |format|
      format.html do
        flash[:business_committers_error] = error_message
        return redirect_to_billing_settings_or_return_to
      end
      format.json do
        render json: { error: error_message }, status: :unprocessable_entity
      end
    end
  end

  sig { params(success_message: String, payload: T::Hash[Symbol, T.untyped]).void }
  def respond_with_success(success_message, payload = {})
    respond_to do |format|
      format.html do
        flash[:business_committers_success] = success_message
        return redirect_to_billing_settings_or_return_to
      end

      format.json { render json: { success: success_message, **payload } }
    end
  end
end
