# typed: true
# frozen_string_literal: true

module TokenExpirable
  extend ActiveSupport::Concern

  # Values added here should also be added to the hydro schema
  # https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/github/v1/oauth_access.proto
  VALID_DEFAULT_EXPIRATIONS = {
    nil => :NONE,
    "7" => :SEVEN_DAYS,
    "30" => :THIRTY_DAYS,
    "60" => :SIXTY_DAYS,
    "90" => :NINETY_DAYS,
    "custom" => :CUSTOM,
    "none" => :NONE
  }

  ExpirableTypes = T.type_alias { T.any(OauthAccess, UserProgrammaticAccess) }

  included do
    T.bind(self, T.any(T.class_of(OauthAccess), T.class_of(UserProgrammaticAccess)))

    attribute :default_expires_at, :string, default: "30"
    attribute :custom_expires_at, :date
  end

  def set_expiration(default_expiration, custom_expiration, allow_custom_default_expires_at: false)
    T.bind(self, ExpirableTypes)

    self.default_expires_at = default_expiration
    self.custom_expires_at = custom_expiration

    field, error_msg = expiration_error(default_expires_at, custom_expires_at, allow_custom_default_expires_at)

    if error_msg.present?
      self.errors.add(field, error_msg)
      return
    end

    # this return handles the edge case where the update page would
    # update the HH::MM::SS even when the custom date picker
    # has the right date chosen.
    return if default_expires_at == "custom" && T.unsafe(expires_at)&.to_date == custom_expires_at

    self.expires_at = get_expiration_date(default_expires_at, custom_expires_at)
  end

  def expiration_error(default_expires_at, custom_expires_at, allow_custom_default_expires_at)
    custom_expires_at = Time.zone.parse(custom_expires_at.to_s)

    if custom_date_blank?(default_expires_at, custom_expires_at)
      return [:custom_expires_at, "can't be blank.  Please choose a date."]
    end

    if custom_date_invalid?(default_expires_at, custom_expires_at)
      return [:custom_expires_at, "is not within the next year."]
    end

    if !allow_custom_default_expires_at && default_expires_at_invalid?(default_expires_at)
      return [:default_expires_at, "is not a valid selection."]
    end

    if blank_expiration?(default_expires_at) && expiration_required?
      [:custom_expires_at, "can't be blank.  Please choose a date."]
    end
  end

  def default_expires_at_invalid?(default_expires_at)
    T.bind(self, ExpirableTypes)

    VALID_DEFAULT_EXPIRATIONS.keys.exclude?(default_expires_at)
  end

  def custom_date_blank?(default_expires_at, custom_expires_at)
    default_expires_at == "custom" && custom_expires_at.blank?
  end

  def custom_date_invalid?(default_expires_at, custom_expires_at)
    return false unless default_expires_at == "custom"

    today = Time.zone.today
    custom_expires_date = custom_expires_at.to_date
    !custom_expires_date.between?(today + 1.day, today + 1.year)
  end

  def get_expiration_date(default_expires_at, custom_expires_at)
    if default_expires_at == "custom"
      Time.zone.parse(custom_expires_at.to_s)
    elsif default_expires_at == "none"
      nil
    else
      Time.zone.now + default_expires_at.to_i.days
    end
  end

  def blank_expiration?(default_expires_at)
    default_expires_at.blank? || default_expires_at == "none"
  end

  # Returns false for PATv1
  # Returns true for PATv2 when owner has infinite_fg_pat_lifetime FF
  # Returns false for PATv2 without FF
  def expiration_required?
    T.bind(self, ExpirableTypes)

    return false unless ProgrammaticAccess.user_type?(self)

    if self.is_a?(UserProgrammaticAccess) && owner.present? && T.must(owner).feature_enabled?(:infinite_fg_pat_lifetime)
      return false
    end

    true
  end
end
