# typed: strict
# frozen_string_literal: true

module ProductSignupUrls
  extend ActiveSupport::Concern

  # Returns the signup path for a given CouponProductTarget.
  sig { params(product_target: T.nilable(CouponProductTarget)).returns(T.nilable(String)) }
  def signup_path_for_product_target(product_target)
    return nil unless product_target

    url_helpers = Rails.application.routes.url_helpers
    case [product_target.product_type, product_target.product_key]
    when [Copilot::PRODUCT_TYPE, Copilot::INDIVIDUAL_PRO_PRODUCT_KEY]
      url_helpers.copilot_pro_signup_new_path
    when [Copilot::PRODUCT_TYPE, Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY]
      url_helpers.copilot_pro_plus_signup_new_path
    when [Copilot::PRODUCT_TYPE, Copilot::INDIVIDUAL_MAX_PRODUCT_KEY]
      url_helpers.copilot_max_signup_new_path
    end
  end
end
