# typed: true
# frozen_string_literal: true

module Api::App::MarketplaceListingHelpers
  include Api::App::InputDependency

  private

  def find_current_app
    current_app_via_authorization_header
  end

  def attempt_login
    @current_user = nil

    if request_credentials.login_password_present?
      if current_app.blank?
        reject_for_bad_credentials!
      end
    end

    return if current_app.present?

    attempt_login_from_integration

    GitHub.context.push(auth: "jwt")
    Audit.context.push(auth: "jwt")

    log_data[:auth] = "jwt"
  end

  def current_marketplace_listing
    return @current_marketplace_listing if defined?(@current_marketplace_listing)
    @current_marketplace_listing = if current_app.present?
      current_app
    else
      current_integration
    end.marketplace_listing
  end

  def find_plan!(param_name: :id)
    plan = current_marketplace_listing.listing_plans.find_by_id(int_id_param!(key: param_name))
    record_or_404(plan)
  end

  def find_account!(param_name: :id)
    return @find_account if defined?(@find_account)

    @find_account = User.find_by(id: int_id_param!(key: param_name))
    record_or_404(@find_account)
  end

  def require_marketplace_listing!
    return true if current_marketplace_listing.present?
    deliver_error! 404, message: "Marketplace listing not found"
  end
end
