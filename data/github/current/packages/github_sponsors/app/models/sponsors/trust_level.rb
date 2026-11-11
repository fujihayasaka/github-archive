# typed: true
# frozen_string_literal: true

class Sponsors::TrustLevel
  class UnprocessableError < StandardError; end

  extend Sponsors::TrustSystem::Instrumentation

  UNTRUSTED_ACCOUNT_AGE_THRESHOLD = 6.months
  NEUTRAL_ACCOUNT_AGE_THRESHOLD = 1.year
  CALCULATED = :calculated
  UNTRUSTED = :untrusted
  NEUTRAL = :neutral
  TRUSTED = :trusted
  # the difference between values and options is subtle,
  # values indicate what trust levels exist, and options
  # represent what trust levels can be set to. The idea
  # that we can return to the calculating the value.
  TRUST_LEVEL_VALUES = [UNTRUSTED, NEUTRAL, TRUSTED].freeze
  TRUST_LEVEL_OPTIONS = (TRUST_LEVEL_VALUES + [CALCULATED]).freeze
  USER_SETTINGS_KEYS = {
    sponsor: :trust_level_as_sponsor,
    sponsorable: :trust_level_as_sponsorable,
  }.freeze
  TARGET_TYPES = [:sponsor, :sponsorable].freeze

  class Result
    attr_reader :target_type, :target, :calculated_trust_level

    ## Trust level result
    #
    # trust_level - Symbol representing the target's trust level (:untrusted, :neutral, or :trusted)
    # calculated_trust_level - The trust level calculated, may differ from trust level if manually set
    # target_type - Symbol whether the target is a :sponsor or :sponsorable; that is,
    #               whether they're the user/org who is funding a sponsorship or
    #               receiving a sponsorship
    # target - The User/Org sponsor or sponsorable (depending on the target type)
    # forced - Boolean indicating whether this result was forced (e.g. manually set) or calculated.
    def initialize(trust_level, calculated_trust_level:, target_type:, target:, forced:)
      raise "Invalid trust level" unless TRUST_LEVEL_VALUES.include?(trust_level)
      raise "Invalid calculated trust level" unless TRUST_LEVEL_VALUES.include?(calculated_trust_level)
      raise "Invalid target type" unless TARGET_TYPES.include?(target_type)

      @trust_level = trust_level
      @calculated_trust_level = calculated_trust_level
      @target_type = target_type
      @target = target
      @forced = forced
    end

    def untrusted?
      @trust_level == UNTRUSTED
    end

    def neutral?
      @trust_level == NEUTRAL
    end

    def trusted?
      @trust_level == TRUSTED
    end

    def forced?
      !!@forced
    end

    def reason
      if forced?
        "Trust level forced."
      elsif untrusted?
        "Account fewer than #{UNTRUSTED_ACCOUNT_AGE_THRESHOLD.in_months.to_i} months old."
      elsif neutral?
        "Account between #{UNTRUSTED_ACCOUNT_AGE_THRESHOLD.in_months.to_i} and " \
          "#{NEUTRAL_ACCOUNT_AGE_THRESHOLD.in_months.to_i} months old."
      else
        "Account more than #{NEUTRAL_ACCOUNT_AGE_THRESHOLD.in_months.to_i} months old."
      end
    end

    def to_s
      @trust_level.to_s
    end
  end

  # Public: Returns the trust level for a funder
  #
  # sponsor - User or Organization funding sponsorships
  #
  # Returns a Sponsors::TrustLevel::Result.
  def self.as_sponsor(sponsor)
    trust_level_result(target: sponsor, target_type: :sponsor)
  end

  # Public: Persists the trust level for a funder
  #
  # actor - User setting the trust level
  # sponsor - User or Organization funding sponsorships
  # trust_level - A symbol from TRUST_LEVEL_VALUES representing the trust level to set.
  #
  # Returns a Sponsors::TrustLevel::Result for the new trust level or raises UnprocessableError on failure.
  def self.set_as_sponsor(actor:, sponsor:, trust_level:)
    set_trust_level(actor: actor, target: sponsor, target_type: :sponsor, trust_level: trust_level)
  end

  # Public: Returns the trust level for a maintainer
  #
  # sponsorable - User or Organization receiving sponsorships
  #
  # Returns a Sponsors::TrustLevel::Result.
  def self.as_sponsorable(sponsorable)
    trust_level_result(target: sponsorable, target_type: :sponsorable)
  end

  # Public: Persists the trust level for a maintainer
  #
  # actor - User setting the trust level
  # sponsor - User or Organization receiving sponsorships
  # trust_level - A symbol (:calculated, :untrusted, :neutral, :trusted) representing the trust level to set.
  #
  # Returns Sponsors::TrustLevel::Result for the new trust level or nil to indicate no action was taken.
  def self.set_as_sponsorable(actor:, sponsorable:, trust_level:)
    set_trust_level(actor: actor, target: sponsorable, target_type: :sponsorable, trust_level: trust_level)
  end

  private_class_method def self.calculate_trust_level(target:)
    created_at = target.created_at

    if created_at.after?(UNTRUSTED_ACCOUNT_AGE_THRESHOLD.ago)
      UNTRUSTED
    elsif created_at.after?(NEUTRAL_ACCOUNT_AGE_THRESHOLD.ago)
      NEUTRAL
    else
      TRUSTED
    end
  end

  private_class_method def self.trust_level_result(target:, target_type:)
    calculated_trust_level = calculate_trust_level(target: target)
    persisted_trust_level = target.settings.get(USER_SETTINGS_KEYS.fetch(target_type)).to_sym
    trust_level, forced = if TRUST_LEVEL_VALUES.include?(persisted_trust_level)
      [persisted_trust_level, true]
    else
      [calculated_trust_level, false]
    end

    Result.new(trust_level,
      calculated_trust_level: calculated_trust_level,
      target_type: target_type,
      target: target,
      forced: forced,
    )
  end

  private_class_method def self.set_trust_level(actor:, target:, target_type:, trust_level:)
    return unless actor&.site_admin?

    old_trust_level = trust_level_result(target: target, target_type: target_type)
    begin
      target.settings.set!(USER_SETTINGS_KEYS.fetch(target_type), trust_level.to_s)
    rescue SettingsCollection::InvalidUpdate
      raise UnprocessableError.new("Could not save trust level #{trust_level} for #{target_type} #{target}")
    end
    new_trust_level = trust_level_result(target: target, target_type: target_type)
    instrument_trust_level_manually_set(old_trust_level, new_trust_level, actor: actor)
    new_trust_level
  end
end
