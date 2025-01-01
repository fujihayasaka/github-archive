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
end
