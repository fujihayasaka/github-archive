# typed: false
# frozen_string_literal: true

module Configurable
  module DiskQuota
    DEFAULT_LOCK_DISK_QUOTA = 100
    DEFAULT_WARN_DISK_QUOTA = 75

    # We have two kinds of sizes so we know to warn before we disable pushes.
    module QuotaKind
      WARN = :warn
      LOCK = :lock

      def self.valid?(kind)
        [WARN, LOCK].include?(kind)
      end
    end

    class InvalidQuota < StandardError; end

    # Public: Gets the current disk quota in gigabytes, 0 means no limit
    #
    # Returns Integer
    def disk_quota(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)

      config.get("git.#{kind}diskquota").try(:to_i) || default_disk_quota(kind: kind)
    end

    def default_disk_quota(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)

      case kind
      when :warn
        DEFAULT_WARN_DISK_QUOTA
      when :lock
        DEFAULT_LOCK_DISK_QUOTA
      end
    end

    # Public: Set a quota for the repository
    #
    # Acceptable values:
    #   0 means no size limit
    #   Setting to the default will clear the setting
    #   Any other integer is a limit in GB.
    #
    # user - User setting the value
    #
    # Returns nothing
    def set_disk_quota(kind:, value:, user:, policy: false)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)

      if value == default_disk_quota(kind: kind) && !policy
        clear_disk_quota(kind: kind, user: user)
      else
        config.set!("git.#{kind}diskquota", value.to_i, user, policy)
      end
    end

    # Public: Clear the quota limit
    # Removes the configuration setting entirely
    #
    # user - User clearing the value
    #
    # Returns nothing
    def clear_disk_quota(kind:, user:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)
      config.delete("git.#{kind}diskquota", user)
    end

    # Public: Indicate if the disk quota sizes can be changed on this object
    #
    # Returns true or false
    def disk_quota_writable?(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)
      config.writable?("git.#{kind}diskquota")
    end

    # Public: Indicate if the disk quota came from higher level via policy
    #
    # Returns true or false
    def disk_quota_policy?(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)
      config.final?("git.#{kind}diskquota")
    end

    # Public: Indicate if the disk quota is set somewhere else
    #
    # Returns true or false
    def disk_quota_inherited?(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)
      config.inherited?("git.#{kind}diskquota")
    end

    # Public: Indicate if the disk quota is set on this object
    #
    # Returns true or false
    def disk_quota_local?(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)
      config.local?("git.#{kind}diskquota")
    end

    # Public: Retrieve the object that has the disk quota value set
    #
    # Returns a Configurable or nil
    def disk_quota_source(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)
      config.source("git.#{kind}diskquota")
    end

    # Public: Where a default value would come from if the current setting is cleared
    #
    # Returns a Configurable or nil
    def disk_quota_default_source(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)
      configuration_default_entry_owner("git.#{kind}diskquota")
    end

    # Public: Where a default value would be if the current setting is cleared
    #
    # Returns a Configurable or nil
    def disk_quota_default_value(kind:)
      raise InvalidQuota(kind) unless QuotaKind.valid?(kind)
      configuration_default_entry_value("git.#{kind}diskquota")
    end
  end
end
