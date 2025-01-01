# typed: strict
# frozen_string_literal: true

module Copilot
  class TokenRefresh
    extend T::Helpers

    include GitHub::Memoizer

    TOKEN_REFRESH_IN         = T.let(1500, Integer)

    TOKEN_REFRESH_DEFAULTS = T.let([
      { low: 0, high: 10, duration: 60 },
      { low: 10, high: 25, duration: 600 },
      { low: 25, high: 50, duration: 900 },
      { low: 50, high: 100, duration: TOKEN_REFRESH_IN },
    ], T::Array[T::Hash[Symbol, Integer]])

    REDIS_TOKEN_REFRESH_IN_KEY = "config:token_refresh_in"

    sig { params(copilot_user: Copilot::User, quota_remaining_percentage: Float).void }
    def initialize(copilot_user, quota_remaining_percentage: 100.0)
      @copilot_user               = T.let(copilot_user, Copilot::User)
      @quota_remaining_percentage = T.let(quota_remaining_percentage, Float)

      # default to 25 minutes
      @token_refresh_in = T.let(TOKEN_REFRESH_IN, Integer)

      if !@copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_free_token_refresh) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        GitHub.logger.info("Feature flag not enabled, using defaults")
        return
      end

      if @quota_remaining_percentage == 100.0
        GitHub.logger.info("Quota is full, using defaults")
        return
      end

      # we need to use this instead of the Copilot::User.limited_user because we don't want to create a user, we just want
      # to see if there is a subscribed limited user
      limited_user = Copilot::LimitedUser.subscribed.find_by(user_id: copilot_user.id)
      unless limited_user.present?
        GitHub.logger.info("User does not have a subscribed limited user record, using defaults")
        return
      end

      load_refresh_values
    rescue StandardError => e # rubocop:todo Lint/RescueException
      # If we fail to load the token values, we don't want to break the app.
      # We'll just log the error and continue on.
      GitHub.logger.error(e, "code.function" => "Copilot::TokenRefresh#initialize", "gh.user.id" => @copilot_user.id)
    end

    sig { returns(Integer) }
    memoize def token_refresh_in
      @token_refresh_in
    end

    sig { void }
    def load_refresh_values
      GitHub.logger.with_named_tags(
        "code.function" => "load_refresh_values",
        "gh.user.id" => @copilot_user.id,
        "gh.copilot.quota_remaining_percentage" => @quota_remaining_percentage,
      ) do
        TOKEN_REFRESH_DEFAULTS.each do |val|
          low, high, duration = val.fetch_values(:low, :high, :duration)
          if @quota_remaining_percentage >= low.to_f && @quota_remaining_percentage < high.to_f
            GitHub.logger.info(
              "Matched quota range",
            {
              "gh.copilot.quota_range.low" => low,
              "gh.copilot.quota_range.high" => high,
              "gh.copilot.quota_range.duration" => duration
            })
            @token_refresh_in = duration
            break
          end
        end
      end
    end
  end
end
