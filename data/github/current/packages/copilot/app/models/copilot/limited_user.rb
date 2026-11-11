# typed: strict
# frozen_string_literal: true

module Copilot
  class LimitedUser < ApplicationRecord::Copilot
    extend Copilot::Helpers
    include GitHub::Memoizer
    include Copilot::Helpers
    include Copilot::Metrics
    include Copilot::Errors
    include Api::Internal::Twirp::Copilot::Helpers

    self.table_name = "copilot_limited_users"

    self.strict_loading_by_default = true

    belongs_to :user, class_name: "::User", strict_loading: false

    validates :user, presence: true

    ALLOWED_FEATURES = T.let(%w[chat completions], T::Array[String])

    scope :subscribed, -> { where.not(subscribed_at: nil) }
    scope :unsubscribed, -> { where(subscribed_at: nil) }

    sig { params(user: ::User).returns(T.nilable(Copilot::LimitedUser)) }
    def self.for_subscribed_user(user)
      where(user_id: user.id).subscribed.first
    end

    sig { returns(T::Class[T.anything]) }
    def sorbet_class
      self.class
    end

    sig { params(user: ::User, skip_copilot_signup_email: T::Boolean).returns(::GitHub::Result) }
    def self.subscribe_user(user, skip_copilot_signup_email: false)
      if Copilot::LimitedUser.for_subscribed_user(user).present?
        GitHub.logger.info("User is already subscribed, returning false")
        return GitHub::Result.new { true }
      end

      if user.is_enterprise_managed?
        GitHub.logger.info("User is enterprise managed")
        GitHub.dogstats.increment("copilot.limited_user.signup.enterprise_managed")
        return GitHub::Result.error("User is enterprise managed")
      end

      # let's do some basic checks first
      if user.spammy?
        GitHub.logger.info("User is spammy")
        GitHub.dogstats.increment("copilot.limited_user.signup.spammy")
        return GitHub::Result.error("User is spammy")
      end

      # the user must also have a verified email
      if user.should_verify_email?
        GitHub.logger.info("User does not have a verified email, not allowing signup")
        GitHub.dogstats.increment("copilot.limited_user.signup.email_not_verified")
        return GitHub::Result.error("You need to verify your email address to sign up for GitHub Copilot Free")
      end

      copilot_user = Copilot::User.new(user)

      if copilot_user.administrative_blocked?
        GitHub.logger.info("User is blocked")
        GitHub.dogstats.increment("copilot.limited_user.signup.blocked")
        return GitHub::Result.error("It appears you are not eligible to sign up for GitHub Copilot Free")
      end

      if copilot_user.has_free_access?
        GitHub.logger.info("User already has free access")
        GitHub.dogstats.increment("copilot.limited_user.signup.already_has_free_access")
        return GitHub::Result.error("You have Copilot Pro for free, you are not eligible to sign up for GitHub Copilot Free")
      end

      if copilot_user.has_trial_subscription?
        GitHub.logger.info("User already has a trial subscription")
        GitHub.dogstats.increment("copilot.limited_user.signup.already_has_trial")
        return GitHub::Result.error("You have a trial subscription, you are not eligible to sign up for GitHub Copilot Free")
      end

      if copilot_user.has_active_subscription?
        GitHub.logger.info("User already has an active subscription")
        GitHub.dogstats.increment("copilot.limited_user.signup.already_has_active")
        return GitHub::Result.error("You already have a Copilot subscription, you are not eligible to sign up for GitHub Copilot Free")
      end

      if copilot_user.has_cfb_access? && !copilot_user.all_assignments_revoked?
        GitHub.logger.info("User already has CFB access")
        GitHub.dogstats.increment("copilot.limited_user.signup.already_has_cfb_access")
        return GitHub::Result.error("You have Copilot through an organization or enterprise, you are not eligible to sign up for GitHub Copilot Free")
      end

      GitHub::Result.new do
        # we need to do this on a write connection, in a transaction
        limited_user = find_by(user: user)
        with_write do
          Copilot::LimitedUser.transaction do
            # let's see if they already have a record, subscribed or not
            # we checked this above but w

            if limited_user.present?
              if limited_user.subscribed?
                GitHub.logger.info("User already has a subscribed record, getting out of here")
                next GitHub::Result.new { true }
              end

              GitHub.logger.info("User already has a record, subscribing")
              GitHub.dogstats.increment("copilot.limited_user.signup.unsubscribed_record")
              limited_user.update(subscribed_at: Time.now)
            else
              GitHub.logger.info("Creating new record")
              GitHub.dogstats.increment("copilot.limited_user.signup.new_record")
              limited_user = create(user: user, subscribed_at: Time.now)
            end
          end
        end

        if FeatureFlag.vexi.enabled?(:copilot_limited_replica_lag_fix, default: false)
          return GitHub::Result.error("Unable to subscribe user to GitHub Copilot Free") unless limited_user.present? && limited_user.valid? && limited_user.persisted?
        else
          updated_limited_user = Copilot::LimitedUser.for_subscribed_user(copilot_user.user_object)
          return GitHub::Result.error("Unable to subscribe user to GitHub Copilot Free") unless updated_limited_user.present?
        end

        copilot_user.set_free_plan_defaults!(copilot_user)

        unless skip_copilot_signup_email
          CopilotLimitedUserMailer.subscribe(user).deliver_later
        end
      end
    end

    sig { void }
    def destroy
      collect_metrics("copilot.limited_user.destroy") do
        with_write do
          expire_redis_keys
          super
        end
      end
    end

    sig { void }
    def expire_redis_keys
      GitHub.logger.info(
        "Expiring redis keys",
        "gh.copilot.limited_user.id": id,
        "gh.copilot.limited_user.user_id": user_id,
      )

      protobuf_reset_date = MonolithTwirp::Copilot::Limiter::V1::ResetDate.new(
        year: reset_date.year,
        month: reset_date.month,
        day: reset_date.day
      )

      CopilotLimiter::Twirp.quota_client.cleanup_free_user_quota(
        copilot_tracking_id: T.must(user).analytics_tracking_id,
        quota_reset_date: protobuf_reset_date,
      )
    rescue StandardError => ex # rubocop:todo Lint/RescueException
      # we do not care if this fails
      GitHub.logger.error("Error calling Twirp", {
        :exception => ex,
        "code.namespace" => self.class.name,
        "code.function" => "expire_redis_keys",
        "gh.catalog_service" => "github/copilot",
        "gh.copilot.limited_user.id" => id,
        "gh.copilot.limited_user.user_id" => user_id,
      })
      GitHub.dogstats.increment("copilot.limited_user.expire_redis_keys.error")
    end

    sig { returns(T::Boolean) }
    def subscribed?
      subscribed_at.present?
    end

    sig { returns(Date) }
    def reset_date
      return Date.new unless subscribed?

      # Assume date is the current month.
      date = Date.current

      current_day = Date.current.day

      # we want to get the day of the month that the user subscribed
      day = subscribed_at.day

      # if that day of the month is AFTER today's day of the month, we know
      # that their reset date is IN THIS SAME MONTH
      # like if they subscribed_at the 19th but today is the second,
      # we want to return the 19th of the current month
      if current_day < day
        GitHub.logger.info(
          "The reset date for this user is still in this month",
          "gh.copilot.limited_user.day": day,
        )
      else
        # we are past the subscribed_at date in this month, so let's look at
        # next month
        GitHub.logger.info(
          "The reset date for this user is in next month",
          "gh.copilot.limited_user.day": day,
        )
        # we want to get that same day for the next month
        date = Date.current.next_month
      end

      if day > date.end_of_month.day
        # if the day is greater than the last day of the month,
        # we need to set it to the last day of the month
        GitHub.logger.info(
          "Day is greater than last day of the month",
          "gh.copilot.limited_user.day": day,
          "gh.copilot.limited_user.month": date.end_of_month.day,
        )
        day = date.end_of_month.day
      end

      Date.new(date.year, date.month, day)
    end

    # This method will return true if the user still has usage left in their counter for the given feature.
    sig { params(feature: String).returns(T::Boolean) }
    def feature_allowed?(feature:) # chat/completions/etc
      collect_metrics("copilot.limited_user.feature_allowed") do
        return false unless user.present?
        return false unless subscribed?
        return false unless ALLOWED_FEATURES.include?(feature)

        get_feature_quota_allowed(feature)
      end
    end

    # This method will return the amount of quota left for the user and the given feature
    #
    # It will return 0 if the feature is invalid or the LimitedUser does not exist
    sig { params(feature: String).returns(Integer) }
    def feature_quota_remaining(feature:) # chat/completions/etc
      collect_metrics("copilot.limited_user.feature_quota_remaining") do
        return 0 unless user.present?
        return 0 unless subscribed?
        return 0 unless ALLOWED_FEATURES.include?(feature)

        get_feature_quota_remaining(feature)
      end
    end

    # This method will return the percentage of quota left for the user and the given feature
    #
    # It will return 0.0 if the feature is invalid or 100.0 if the LimitedUser does not exist/subscribed
    sig { params(feature: String).returns(Float) }
    def feature_quota_percentage_remaining(feature:) # chat/completions/etc
      collect_metrics("copilot.limited_user.feature_quota_percentage_remaining") do
        return 100.0 unless user.present?
        return 100.0 unless subscribed?
        return 0.0 unless ALLOWED_FEATURES.include?(feature)

        get_feature_quota_percentage_remaining(feature)
      end
    end

    # This method will return a hash of the features and the amount of quota they have remaining
    sig { returns(T::Hash[String, Integer]) }
    def quotas_remaining
      collect_metrics("copilot.limited_user.quotas_remaining") do
        return {} unless user.present?
        return {} unless subscribed?

        features = T.let({}, T::Hash[String, Integer])
        ALLOWED_FEATURES.each do |feature|
          features[feature] = get_feature_quota_remaining(feature)
        end

        features
      end
    end

    # This method will return a hash of the features and the percentage of quota they have remaining
    sig { returns(T::Hash[String, Float]) }
    def quota_percentages_remaining
      collect_metrics("copilot.limited_user.quota_percentages_remaining") do
        return {} unless user.present?
        return {} unless subscribed?

        features = T.let({}, T::Hash[String, Float])
        ALLOWED_FEATURES.each do |feature|
          features[feature] = get_feature_quota_percentage_remaining(feature)
        end

        features
      end
    end

    # this will actually set the count of events for the user so that they have
    # the given amount of quota left for the given feature
    #
    # so if the quota parameter is 100, and the max quota is 100, then we will
    # set the redis value to 0, and the user will have 100 events left for the month
    # if the quota parameter is 100, and the max quota is 50, then we will set the
    # redis value to 50, and the user will have 50 events left for the month
    #
    # it will return true if the quota was set successfully
    sig { params(feature: String, quota: Integer).returns(GitHub::Result) }
    def set_quota_remaining(feature:, quota:)
      collect_metrics("copilot.limited_user.set_quota_remaining") do
        GitHub.logger.with_named_tags({
          "code.function": "set_quota_remaining",
          "gh.copilot.free_feature": feature,
          "gh.copilot.free_quota": quota,
          "gh.copilot.limited_user.id": id,
          "gh.copilot.limited_user.user_id": user_id,
          "gh.copilot.limited_user.subscribed_at": subscribed_at,
        }) do
          GitHub::Result.new do
            raise "User not found" unless user.present?

            copilot_user = Copilot::User.new(T.must(user))

            # we need to make sure the feature is valid
            unless ALLOWED_FEATURES.include?(feature)
              GitHub.logger.info("Invalid feature")
              raise "Invalid feature #{feature}"
            end

            # we need to still have a user
            unless user.present?
              GitHub.logger.info("User missing")
              raise "User missing"
            end

            # we need to make sure the user is subscribed
            unless subscribed?
              GitHub.logger.info("User not subscribed")
              raise "User not subscribed"
            end

            # we need to make sure the quota is not negative
            if quota.negative?
              GitHub.logger.info("Quota is negative")
              raise "Quota must be greater than 0"
            end

            # if the feature is enabled, we will send the quota to twirp
            CopilotLimiter::Twirp.quota_client.set_free_user_quota(
              copilot_tracking_id: T.must(user).analytics_tracking_id,
              feature: feature,
              quota: quota,
              twirp_access_type: twirp_access_type(copilot_user.copilot_authorizer_object_no_snippy.access_type)
            )
            GitHub.logger.info("Quota set in twirp")
            return GitHub::Result.new { true }
          end
        end
      end
    end

    sig { params(feature: String).returns(T::Boolean) }
    def get_feature_quota_allowed(feature)
      remaining = get_feature_quota_remaining(feature)

      remaining > 0
    end

    sig { params(feature: String).returns(Integer) }
    def get_feature_quota_remaining(feature)
      collect_metrics("copilot.limited_user.get_feature_quota_remaining") do
        # this is the current max quota for the feature - this applies to all limited users
        monthly_quota = self.class.monthly_quota_limits[feature].to_i # this is an integer

        # we need to get the current count for the feature for the user
        used_quota = load_quota_from_twirp.fetch(feature, 0) # returns an Integer

        # so, the quota remaining is the max quota minus the used quota
        rem = monthly_quota - used_quota

        # rem can't be less than 0
        [rem, 0].max
      end
    end

    # This method will return the percentage of quota left for the user and the given feature
    sig { params(feature: String).returns(Float) }
    def get_feature_quota_percentage_remaining(feature) # chat/completions/etc
      collect_metrics("copilot.limited_user.get_feature_quota_percentage_remaining") do
        # this is the current max quota for the feature - this applies to all limited users
        monthly_quota = self.class.monthly_quota_limits[feature].to_f

        # we need to get the current count for the feature for the user
        value = load_quota_from_twirp.fetch(feature, 0) # returns an integer

        # let's convert the value to a float
        used_quota = value.to_f

        # so, the quota remaining is the max quota minus the used quota
        rem = monthly_quota - used_quota

        # rem can't be less than 0
        rem = [rem, 0].max

        # so, the quota remaining is the max quota minus the used quota
        (rem / monthly_quota) * 100
      end
    end

    # This will return the key for the given user and feature
    sig { params(feature: String).returns(String) }
    def feature_count_key(feature)
      if user.nil?
        GitHub.logger.warn("LimitedUser has a nil User", "gh.copilot.limited_user.id": id)
        return ""
      end
      "#{feature}:#{T.must(user).analytics_tracking_id}"
    end

    sig { returns(T::Hash[String, Integer]) }
    def self.monthly_quota_limits
      Copilot::DEFAULT_QUOTAS
    end

    private

    sig { returns(String) }
    memoize def cache_key
      "copilot:#{T.must(user).analytics_tracking_id}"
    end

    sig { returns(T::Hash[String, Integer]) }
    memoize def load_quota_from_twirp
      GitHub.dogstats.distribution_time("#copilot.limited_user.load_quota_from_twirp.latency") do
        values = GitHub.cache.fetch(
          cache_key,
          ttl: 1.minute,
          stats_key: "copilot.limited_user.quota_cache",
        ) do
          return {} unless user.present?

          GitHub.logger.with_named_tags({
            "code.function": "load_quota_from_twirp",
            "code.namespace": "Copilot::LimitedUser",
            "gh.user.analytics_tracking_id": T.must(user).analytics_tracking_id,
          }) do
            use_get_quota_remaining = T.must(user).feature_flag_enabled_or_raise?(:copilot_limited_user_get_quota_remaining) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            GitHub.dogstats.increment("copilot.limited_user.load_quota_from_twirp", tags: { use_get_quota_remaining: use_get_quota_remaining })

            if use_get_quota_remaining
              GitHub.logger.info("Calling GetQuotaRemaining")
              quota_remaining = CopilotLimiter::Twirp.quota_client.get_quota_remaining(
                copilot_tracking_id: T.must(user).analytics_tracking_id,
                twirp_access_type: ::MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_FREE_LIMITED_COPILOT,
              )
              # what we get here is a hash of UserQuotaRemaining which has an entitlement and remaining
              # the get_free_user_quota method will return back the count of usage and then we use the
              # monthly quota to do math so we need to flip that here annoyingly
              chat_remaining = quota_remaining.dig(:chat, :remaining).to_i || 0
              completions_remaining = quota_remaining.dig(:completions, :remaining).to_i || 0
              GitHub.logger.info(
                "Loaded GetQuotaRemainingResponse",
                "gh.copilot.limited_user.quota_remaining": quota_remaining,
                "gh.copilot.limited_user.chat_remaining": chat_remaining,
                "gh.copilot.limited_user.completions_remaining": completions_remaining,
              )

              return {
                "chat" => chat_remaining,
                "completions" => completions_remaining,
              }
            end

            # this will get the free quota from twirp
            return CopilotLimiter::Twirp.quota_client.get_free_user_quota(
              copilot_tracking_id: T.must(user).analytics_tracking_id,
            ).map do |feature, quota|
              [feature.to_s, quota.to_i]
            end.to_h
          end
        end

        values
      end
    end
  end
end
