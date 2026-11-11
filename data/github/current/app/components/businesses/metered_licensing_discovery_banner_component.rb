# typed: true
# frozen_string_literal: true

class Businesses::MeteredLicensingDiscoveryBannerComponent < ApplicationComponent
  include Licensing::DismissalHelper

  attr_reader :business, :current_user

  def initialize(business:, current_user:)
    @business = business
    @current_user = current_user
  end

  def self.dismissal_key(business_id:, user_id:)
    "metered_conversion_banner.#{business_id}.#{user_id}"
  end

  sig { void }
  def dismiss_banner
    dismiss(self.class.dismissal_key(business_id: business.id, user_id: current_user.id), expires: 30.days.from_now)
  end

  sig { returns(T::Boolean) }
  def is_banner_dismissed?
    is_dismissed?(self.class.dismissal_key(business_id: business.id, user_id: current_user.id))
  end

  def render?
    return false if is_banner_dismissed?

    business.eligible_for_self_serve_metered_transition?(user: current_user)
  rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
    false
  end
end
