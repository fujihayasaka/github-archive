# typed: true
# frozen_string_literal: true

module UserEntitySerializer
  USER_TYPES = {
    "Bot" => :BOT,
    "Organization" => :ORGANIZATION,
    "ProgrammaticAccessBot" => :PROGRAMMATIC_ACCESS_BOT,
    "User" => :USER,
  }

  def self.serialize(entity)
    spamurai_classification = if entity.spammy?
      :SPAMMY
    elsif entity.hammy?
      :HAMMY
    else
      :SPAMURAI_CLASSIFICATION_UNKNOWN
    end

    {
      id: entity.id,
      login: entity.login,
      display_login: entity.display_login,
      type: USER_TYPES.fetch(entity.class.name, :UNKNOWN),
      billing_plan: entity.plan.try(:display_name),
      spammy: entity.spammy?,
      suspended: entity.suspended?,
      spamurai_classification: spamurai_classification,
      global_relay_id: entity.global_relay_id,
      next_global_id: entity.next_global_id,
      created_at: entity.created_at,
      analytics_tracking_id: entity.analytics_tracking_id,
      is_enterprise_managed: entity.is_enterprise_managed?,
      time_zone_name: entity.time_zone_name,
      avatar_url: entity.primary_avatar_url,
    }
  end
end
