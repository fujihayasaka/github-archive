# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  class Reason
    private_class_method :new

    attr_reader :reason
    def initialize(reason)
      @reason = reason
    end

    REASONS = {
      manual_enrollment: 127,
      published_package: 1,
      published_app: 2,
      created_release: 3,
      enterprise_org_admin: 4,
      open_ssf_admin: 5,
      open_ssf_contributor: 6,
      registry_repo_admin: 7,
      registry_repo_contributor: 8,
    }
    private_constant :REASONS

    def self.from_value(value)
      raise ArgumentError, "Invalid enum value: #{value}" if REASONS.key(value).nil?
      new(REASONS.key(value))
    end

    def self.from_symbol(reason)
      raise ArgumentError, "Invalid reason: #{reason}" if REASONS[reason].nil?
      new(reason)
    end

    # The amount of time that a user has to enable two-factor authentication before it is enforced on their account.
    def grace_period
      45.days
    end

    def to_value
      REASONS[reason]
    end

    def to_s
      reason.to_s
    end
  end
end
