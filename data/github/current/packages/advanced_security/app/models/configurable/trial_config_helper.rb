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
      @ended_at_key = "#{sku_name}_trial_ended_at"
      @count_key = "#{sku_name}_trial_count"
      @trial_type_key = "#{sku_name}_trial_type"
    end

    sig { params(actor: User, start_date: Date, days: Integer, reset_on_expiration: T::Boolean).void }
    def enable_trial(actor:, start_date:, days:, reset_on_expiration: false)
      # Increment trial count when starting a new trial
      increment_trial_count(actor:)

      set_number_of_days(actor: actor, days: days)
      @rec.config.enable(@trial_key, actor)
      @rec.config.set(@start_date_key, start_date, actor)
      set_reset_on_expiration(actor: actor, reset_on_expiration: reset_on_expiration)
    end

    # Disable the trial. This also removes the config entries for the number of days and start date.
    # The trial end date is set to the current date before cleanup (for historical tracking and cooldown calculations).
    sig { params(actor: User).void }
    def disable_trial(actor:)
      set_ended_at(actor:, date: Date.current)

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

    # Returns true if the trial is both enabled and not expired
    sig { returns(T::Boolean) }
    def trial_active?
      return false unless trial_enabled?

      expires = expires_at
      return false unless expires.present?

      expires > Date.current
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

    # Returns the date when the trial ended, or nil if it hasn't ended yet.
    # This persists after trial cleanup unlike start_date.
    sig { returns(T.nilable(Date)) }
    def ended_at
      ended_at_val = @rec.config.get(@ended_at_key)
      return nil unless ended_at_val.present?
      T.let(ended_at_val.to_date, Date)
    end

    # Sets the trial ended at date to the given date.
    sig { params(actor: User, date: Date).void }
    def set_ended_at(actor:, date:)
      @rec.config.set(@ended_at_key, date, actor)
    end

    # Returns the number of trials that have been used for this SKU.
    # Defaults to 0 if not set.
    sig { returns(Integer) }
    def trial_count
      count_val = @rec.config.get(@count_key)
      return 0 unless count_val.present?
      count_val.to_i
    end

    # Increments the trial count by 1.
    sig { params(actor: User).void }
    def increment_trial_count(actor:)
      current_count = trial_count
      @rec.config.set(@count_key, current_count + 1, actor)
    end

    # Returns the trial type (e.g., :sales_led, :ghas_stand_alone, :digital_front_door)
    # Returns nil if not set.
    sig { returns(T.nilable(Symbol)) }
    def trial_type
      trial_type_val = @rec.config.get(@trial_type_key)
      return nil unless trial_type_val.present?
      trial_type_val.to_sym
    end

    # Sets the trial type. Valid values are :sales_led, :ghas_stand_alone, :digital_front_door
    sig { params(actor: User, trial_type: Symbol).void }
    def set_trial_type(actor:, trial_type:)
      valid_types = [:sales_led, :ghas_stand_alone, :digital_front_door]
      raise ArgumentError, "Invalid trial_type: #{trial_type}. Must be one of #{valid_types.join(', ')}" unless valid_types.include?(trial_type)
      @rec.config.set(@trial_type_key, trial_type.to_s, actor)
    end
  end
end
