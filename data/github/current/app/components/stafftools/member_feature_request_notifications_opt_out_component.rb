# typed: true
# frozen_string_literal: true

class Stafftools::MemberFeatureRequestNotificationsOptOutComponent < ApplicationComponent
  attr_reader :entity

  def initialize(entity:)
    @entity = entity
  end

  private

  def render?
    GitHub.dotcom_request? && (entity.is_a?(Business) || entity.is_a?(Organization))
  end

  def entity_description
    entity.is_a?(Business) ? "enterprise" : "organization"
  end

  def form_path
    if entity.is_a?(::Business)
      stafftools_enterprise_member_feature_request_notifications_opt_out_path(entity)
    else
      stafftools_user_member_feature_request_notifications_opt_out_path(entity)
    end
  end
end
