# typed: true
# frozen_string_literal: true

module User::ThirdPartyAnalyticsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  ANALYTICS_TRACKING_ID_LENGTH = 32

  class_methods do
    def generate_analytics_tracking_id
      SecureRandom.hex(ANALYTICS_TRACKING_ID_LENGTH / 2)
    end
  end

  def identify_to_google_analytics?
    return false if GitHub.enterprise?
    analytics_tracking_id.present?
  end

  def set_analytics_tracking_id
    return if GitHub.enterprise?

    potential_tracking_id = User.generate_analytics_tracking_id

    while User.exists?(analytics_tracking_id: potential_tracking_id) do
      potential_tracking_id = User.generate_analytics_tracking_id
    end

    self.analytics_tracking_id = potential_tracking_id
  end
end
