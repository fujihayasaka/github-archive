# typed: true
# frozen_string_literal: true

module Configurable
  # This is a little helper for tracking the status of a trial using a record object's configuration.
  #
  # A trial's status consists of:
  # - enablement state (boolean)
  # - length of trial (in days)
  # - start date
  #
  # Enablement and expiration are independent: an expired trial can still be enabled, and a disabled trial can be
  # unexpired.
  class TrialConfigHelper
    sig { params(sku_name: String).returns(String) }
    def self.trial_key(sku_name)
      "#{sku_name}_trial"
    end

    sig { params(rec: Configurable, sku_name: String, max_days: Integer).void }
    def initialize(rec:, sku_name:, max_days:)
      @rec = rec
      @max_days = max_days
      @trial_key = self.class.trial_key(sku_name)
      @start_date_key = "#{sku_name}_trial_start_date"
      @days_key = "#{sku_name}_trial_number_of_days"
      @reset_key = "#{sku_name}_trial_reset_on_expiration"
    end

    sig { params(actor: User, start_date: Date, days: Integer, reset_on_expiration: T::Boolean).void }
    def enable_trial(actor:, start_date:, days:, reset_on_expiration: false)
      set_number_of_days(actor: actor, days: days)
      @rec.config.enable(@trial_key, actor)
      @rec.config.set(@start_date_key, start_date, actor)
      set_reset_on_expiration(actor: actor, reset_on_expiration: reset_on_expiration)
    end

    # Disable the trial. This also removes the config entries for the number of days and start date.
    sig { params(actor: User).void }
    def disable_trial(actor:)
      @rec.config.delete(@trial_key, actor)
      @rec.config.delete(@start_date_key, actor)
      @rec.config.delete(@days_key, actor)
      @rec.config.delete(@reset_key, actor)
    end

    # Returns true if the trial is enabled, false otherwise. Note that enablement is independent of expiration.
    sig { returns(T::Boolean) }
    def trial_enabled?
      return false unless @rec.config.local?(@trial_key)
      @rec.config.enabled?(@trial_key)
    end

    sig { returns(T.nilable(Date)) }
    def start_date
      start_date_val = @rec.config.get(@start_date_key)
      return nil unless start_date_val.present?
      T.let(start_date_val.to_date, Date)
    end

    sig { returns(T.nilable(Integer)) }
    def number_of_days
      val = @rec.config.get(@days_key)
      return nil unless val.present?
      val.to_i
    end

    sig { params(actor: User, days: Integer).void }
    def set_number_of_days(actor:, days:)
      raise ArgumentError, "days must be positive" if days <= 0
      raise ArgumentError, "too many days" if days > @max_days
      @rec.config.set(@days_key, days, actor)
    end

    sig { returns(T.nilable(Date)) }
    def expires_at
      days = number_of_days
      return nil unless days.present?
      start = start_date
      return nil unless start.present?
      start + days.days
    end

    sig { returns(T::Boolean) }
    def reset_on_expiration?
      reset_val = @rec.config.get(@reset_key)
      return false unless reset_val.present?
      reset_val == "1"
    end

    sig { params(actor: User, reset_on_expiration: T::Boolean).void }
    def set_reset_on_expiration(actor:, reset_on_expiration:)
      @rec.config.set(@reset_key, reset_on_expiration, actor)
    end
  end
end
