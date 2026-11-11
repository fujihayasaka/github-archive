# typed: true
# frozen_string_literal: true

# Allow Businesses and Organizations to opt out of member feature request notifications.
module Configurable::MemberFeatureRequestNotificationsOptOut
  extend T::Helpers

  requires_ancestor { Object }
  requires_ancestor { Configurable }

  KEY = "member_feature_request_notifications_opt_out".freeze

  def opt_out_of_member_feature_request_notifications(actor: nil)
    config.enable!(KEY, actor)
  end

  def opt_in_to_member_feature_request_notifications(actor: nil)
    config.delete(KEY, actor)
  end

  def opted_out_of_member_feature_request_notifications?
    config.enabled?(KEY)
  end
end
