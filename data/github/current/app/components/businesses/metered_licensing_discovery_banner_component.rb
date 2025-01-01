# typed: true
# frozen_string_literal: true

class Businesses::MeteredLicensingDiscoveryBannerComponent < ViewComponent::Base

  attr_reader :business, :current_user

  def initialize(business:, current_user:)
    @business = business
    @current_user = current_user
  end

  def metered_amount_saved
    @metered_amount_saved ||= business.metered_amount_saved
  end

  def render?
    on_licensing_page = GitHub.billing_enabled? && helpers.current_page?(helpers.enterprise_licensing_path(business))
    business.eligible_for_self_serve_metered_transition?(current_user: current_user, on_licensing_page: on_licensing_page)
  rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
    false
  end
end
