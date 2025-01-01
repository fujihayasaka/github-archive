# typed: strict
# frozen_string_literal: true

module Copilot
  class LimitedUser < ApplicationRecord::Copilot
    extend Copilot::Helpers
    include GitHub::Memoizer
    include Copilot::Helpers
    include Copilot::Metrics
    include Copilot::Errors

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

    sig { params(user: ::User).returns(::GitHub::Result) }
    def self.subscribe_user(user)
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

      if copilot_user.has_cfb_access?
        GitHub.logger.info("User already has CFB access")
        GitHub.dogstats.increment("copilot.limited_user.signup.already_has_cfb_access")
        return GitHub::Result.error("You have Copilot through an organization or enterprise, you are not eligible to sign up for GitHub Copilot Free")
      end

      GitHub::Result.new do
        limited_user = T.let(Copilot::LimitedUser.new, T.nilable(Copilot::LimitedUser))

        # we need to do this on a write connection, in a transaction
        with_write do
          Copilot::LimitedUser.transaction do
            # let's see if they already have a record, subscribed or not
            # we checked this above but w
            limited_user = find_by(user_id: user.id)

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
              limited_user = create(user_id: user.id, subscribed_at: Time.now)
            end
          end
        end

        updated_limited_user = Copilot::LimitedUser.for_subscribed_user(copilot_user.user_object)
        return GitHub::Result.error("Unable to subscribe user to GitHub Copilot Free") unless updated_limited_user.present?

        copilot_user.set_free_plan_defaults!(copilot_user)
        CopilotLimitedUserMailer.subscribe(user).deliver_later
      end
    end

    sig { void }
    def destroy
      collect_metrics("copilot.limited_user.destroy") do
        with_write do
          cleanup_redis_keys
          super
        end
      end
    end

    sig { void }
    def cleanup_redis_keys
      GitHub.logger.info("Cleaning up redis keys", "gh.copilot.limited_user.id": id, "gh.copilot.limited_user.user_id": user_id)
      Copilot.limiter_redis.pipelined do |pipeline|
        ALLOWED_FEATURES.each do |feature|
          pipeline.del(feature_count_key(feature))
        end
      end
    rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS, ::Redis::BaseError => e
      # this is not a blocker, but we want to know if it happens
      GitHub.logger.error("Failed to cleanup redis keys", "error": e.message)

      Copilot::ErrorReporter.report!(
        Copilot::Errors::LimitedUserError.from_error(e),
        extra_details: {
          "gh.copilot.limited_user.id" => id,
          "gh.copilot.limited_user.user_id" => user_id,
          "gh.copilot.limited_user.subscribed_at" => subscribed_at,
        }
      )
    end

    sig { returns(T::Boolean) }
    def subscribed?
      subscribed_at.present?
    end

    sig { returns(Date) }
    def reset_date
      collect_metrics("copilot.limited_user.reset_date") do
        return Date.new unless user.present?
        return Date.new unless subscribed?

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
          reset_date = Date.new(Date.current.year, Date.current.month, day)
        else
          # we are past the subscribed_at date in this month, so let's look at
          # next month
          GitHub.logger.info(
            "The reset date for this user is in next month",
            "gh.copilot.limited_user.day": day,
          )
          # we want to get that same day for the next month
          next_month = Date.current.next_month

          if day > next_month.end_of_month.day
            # if the day is greater than the last day of the next month,
            # we need to set it to the last day of the next month
            GitHub.logger.info(
              "Day is greater than last day of month",
              "gh.copilot.limited_user.day": day,
              "gh.copilot.limited_user.next_month": next_month.end_of_month.day,
            )
            day = next_month.end_of_month.day
          end

          reset_date = Date.new(next_month.year, next_month.month, day)
        end
        reset_date
      end
    rescue Date::Error => e
      GitHub.dogstats.increment("copilot.limited_user.reset_date.error")
      rdate = Date.current.next_month.end_of_month

      GitHub.logger.error("Error loading reset date, defaulting to the end of next month", {
        :exception => e,
        "code.namespace" => self.class.name,
        "code.function" => "reset_date",
        "gh.catalog_service" => "github/copilot",
        "gh.copilot.limited_user.id" => id,
        "gh.copilot.limited_user.user_id" => user_id,
        "gh.copilot.limited_user.subscribed_at" => subscribed_at,
        "gh.copilot.limited_user.reset_date" => rdate
      })

      rdate
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

            # we need to get the current quota for the feature
            current_max_quota = Copilot::Quotas.monthly_quotas[feature].to_i
            GitHub.logger.info("Current max quota", "gh.copilot.current_max_quota": current_max_quota)

            # so the quota can't be more than the max quota, so we need to set it to the lesser of the two
            new_quota = [quota, current_max_quota].min
            GitHub.logger.info("New quota", "gh.copilot.new_quota": new_quota)

            # now the new quota needs to be taken away from the max quota to get the new value
            updated_quota = current_max_quota - new_quota
            GitHub.logger.info("Updated quota", "gh.copilot.updated_quota": updated_quota)

            key = feature_count_key(feature)
            GitHub.logger.info("Key", "gh.copilot.key": key)

            raise "Invalid feature" unless key.present?

            result = Copilot::LimiterRedis.set(
              key,
              updated_quota,
            )

            GitHub.logger.info("Redis set result", result: result)

            if result == "OK"
              GitHub.logger.info("Success")
              GitHub.dogstats.increment("copilot.limited_user.set_quota_remaining.success")
              next true
            end

            GitHub.logger.info("Failed")
            GitHub.dogstats.increment("copilot.limited_user.set_quota_remaining.failed")
            raise "Failed to set quota"
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
        monthly_quota = Copilot::DEFAULT_QUOTAS[feature].to_i # this is an integer

        # we need to get the current count for the feature for the user
        used_quota = load_quota_from_redis.fetch(feature, 0) # returns an Integer

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
        monthly_quota = Copilot::DEFAULT_QUOTAS[feature].to_f

        # we need to get the current count for the feature for the user
        value = load_quota_from_redis.fetch(feature, 0) # returns an integer

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

    private

    sig { returns(String) }
    memoize def cache_key
      "copilot:#{T.must(user).analytics_tracking_id}"
    end

    sig { returns(T::Hash[String, Integer]) }
    memoize def load_quota_from_redis
      values = GitHub.cache.fetch(
        cache_key,
        ttl: 1.minute,
        stats_key: "copilot.limited_user.quota_cache",
      ) do
        # get the feature count keys for this year
        keys = ALLOWED_FEATURES.map do |feature|
          feature_count_key(feature)
        end

        Copilot::LimiterRedis.mget(keys).map do |k, v|
          # the keys come back as feature:tracking_id
          feature = k.split(":").first.to_s

          [feature, v.to_i]
        end.to_h
      end

      values
    rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS, ::Redis::BaseError => e
      # if we get an error, just return the monthly quota
      GitHub.dogstats.increment("copilot.limited_user.load_quota_from_redis.error")

      GitHub.logger.error("Error loading quota from redis", {
        exception: e,
        "gh.copilot.limited_user.id": id,
        "gh.copilot.limited_user.user_id": user_id,
        "gh.copilot.limited_user.subscribed_at": subscribed_at,
      })

      Copilot::ErrorReporter.report!(
        Copilot::Errors::LimitedUserError.from_error(e),
        extra_details: {
          "gh.copilot.limited_user.id" => id,
          "gh.copilot.limited_user.user_id" => user_id,
          "gh.copilot.limited_user.subscribed_at" => subscribed_at,
        }
      )
      Copilot::DEFAULT_QUOTAS
    end
  end
end
