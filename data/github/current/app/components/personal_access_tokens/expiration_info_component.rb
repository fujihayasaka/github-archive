# typed: true
# frozen_string_literal: true

class PersonalAccessTokens::ExpirationInfoComponent < ApplicationComponent
  attr_reader :expiration_time, :regeneration_path

  delegate :human_expiration_date, to: :helpers

  def initialize(expiration_time: nil, regeneration_path: "")
    unless valid_expiration?(expiration_time)
      raise ArgumentError, "Expiration time must be a Time object or nil"
    end

    @expiration_time = expiration_time
    @regeneration_path = regeneration_path
  end

  def valid_expiration?(expiration_time)
    return true if expiration_time.nil?
    return true if expiration_time == :expired
    return true if expiration_time.is_a?(Time)

    false
  end

  def expiration_time_set?
    expiration_time.present?
  end

  def expiring_soon?
    return false unless expiration_time_set?

    expiration_time.between?(Time.now, Time.now + 3.days)
  end

  def expired?
    return false unless expiration_time_set?
    return true if expiration_time == :expired

    expiration_time < Time.now
  end

  memoize def id
    "expiration-#{SecureRandom.hex(4)}"
  end

  memoize def link_component_attributes
    {}.tap do |attr|
      attr[:id]        = id
      attr[:color]     = :attention
      attr[:href]      = regeneration_path.present? ? regeneration_path : ""
      attr[:underline] = regeneration_path.present? ? true : false

      if regeneration_path.present?
        attr[:description] = "To set a new expiration date, you must regenerate the token."
      else
        attr[:style] = "cursor: text"
      end
    end
  end

  def render_tooltip?
    regeneration_path.present?
  end
end
