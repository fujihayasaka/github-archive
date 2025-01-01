# typed: strict
# frozen_string_literal: true

module Copilot
  class TokenExpiration
    extend T::Helpers

    include GitHub::Memoizer

    TOKEN_EXPIRATION_SECONDS = T.let(1800, Integer)

    TOKEN_EXPIRATION_DEFAULTS = T.let([
      { low: 0, high: 10, duration: 300 },
      { low: 10, high: 25, duration: 900 },
      { low: 25, high: 50, duration: 1200 },
      { low: 50, high: 100, duration: TOKEN_EXPIRATION_SECONDS },
    ], T::Array[T::Hash[Symbol, Integer]])

    REDIS_TOKEN_EXPIRATION_KEY = "config:token_expiration"

    sig { params(copilot_user: Copilot::User, quota_remaining_percentage: Float).void }
    def initialize(copilot_user, quota_remaining_percentage: 100.0)
      @copilot_user               = T.let(copilot_user, Copilot::User)
      @quota_remaining_percentage = T.let(quota_remaining_percentage, Float)

      # default to 30 minutes
      @token_expiration = T.let(TOKEN_EXPIRATION_SECONDS, Integer)

      if !@copilot_user.user_object.feature_enabled?(:copilot_free_token_refresh)
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

      load_expiration_values
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      # If we fail to load the token values, we don't want to break the app.
      # We'll just log the error and continue on.
      GitHub.logger.error(e, "code.function" => "Copilot::TokenExpiration#initialize", "gh.user.id" => @copilot_user.id)
    end

    sig { returns(Integer) }
    memoize def token_expiration
      @token_expiration
    end

    sig { void }
    def load_expiration_values
      GitHub.logger.with_named_tags(
        "code.function" => "load_expiration_values",
        "gh.user.id" => @copilot_user.id,
        "gh.copilot.quota_remaining_percentage" => @quota_remaining_percentage,
      ) do
        TOKEN_EXPIRATION_DEFAULTS.each do |val|
          low, high, duration = val.fetch_values(:low, :high, :duration)
          if @quota_remaining_percentage >= low.to_f && @quota_remaining_percentage < high.to_f
            GitHub.logger.info(
              "Matched quota range",
            {
              "gh.copilot.quota_range.low" => low,
              "gh.copilot.quota_range.high" => high,
              "gh.copilot.quota_range.duration" => duration
            })
            @token_expiration = duration
            break
          end
        end
      end
    end
  end
end
