# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module ProgrammaticAccess
  USER_TYPE = UserProgrammaticAccess

  TYPES = [
    USER_TYPE
  ]

  NOTIFIABLE_EVENTS_TTL = {
    created: 1.hour,
    regenerated: 1.hour,
    expiration_warning: 1.day,
    expired: 1.day
  }
  NOTIFICATION_RESTRAIN_PREFIX = "programmatic_access_email_notification"
  EXPIRATION_WARNING_THRESHOLDS = {
    "1d" => "1 day",
    "7d" => "7 days",
  }

  def self.for(owner)
    case owner
    when ::User
      UserProgrammaticAccess.where(owner: owner)
    end
  end

  def self.granted_on(target)
    case target
    when ::Organization
      UserProgrammaticAccess
        .joins(:organization_programmatic_access_grants)
        .where(organization_programmatic_access_grants: { target: target })
    else
      UserProgrammaticAccess
        .joins(:user_programmatic_access_grants)
        .where(user_programmatic_access_grants: { target: target })
    end
  end

  def self.none
    UserProgrammaticAccess.none
  end

  def self.exists?(access_id)
    UserProgrammaticAccess.exists?(access_id)
  end

  def self.find(access_id)
    UserProgrammaticAccess.find(access_id)
  end

  def self.find_or_nil(access_id)
    UserProgrammaticAccess.find_by(id: access_id)
  end

  def self.new_access(owner, attrs = {})
    case owner
    when ::User
      UserProgrammaticAccess.new(owner: owner, **attrs)
    end
  end

  def self.create_with_grant_and_token(attributes = {})
    ProgrammaticAccessWithGrantAndToken::Creator.perform(attributes)
  end

  # Returns a ProgrammaticAccessToken::Result.
  def self.destroy(access, explanation)
    ProgrammaticAccess::Destroyer.perform(access, explanation)
  end

  def self.user_type?(access)
    access.is_a?(UserProgrammaticAccess)
  end

  def self.owner_can_be_notified?(access, event_type:)
    interval = NOTIFIABLE_EVENTS_TTL[event_type]
    return false unless interval

    GitHub::ActionRestraint.perform?(
      NOTIFICATION_RESTRAIN_PREFIX,
      interval: interval,
      event_type: event_type,
      user_id: access.user_id,
      access_id: access.id,
    )
  end
end
