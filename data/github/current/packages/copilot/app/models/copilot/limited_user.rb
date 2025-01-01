# typed: strict
# frozen_string_literal: true

module Copilot
  class LimitedUser < ApplicationRecord::Copilot
    extend Copilot::Helpers
    include GitHub::Memoizer
    include Copilot::Helpers
    include Copilot::Metrics

    self.table_name = "copilot_limited_users"

    self.strict_loading_by_default = true

    belongs_to :user, class_name: "::User", strict_loading: false

    validates :user, presence: true

    ALLOWED_FEATURES = T.let(%w[chat completions], T::Array[String])
    QUOTAS_KEY = T.let("config:quotas".freeze, String)

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

    sig { params(copilot_user: Copilot::User).returns(T.nilable(Copilot::LimitedUser)) }
    def self.find_for_copilot_user(copilot_user)
      return if !copilot_user.user_object.feature_enabled?(:copilot_free_limited_user)

      copilot_user.collect_metrics("copilot.limited_user.find_for_copilot_user") do
        return nil if copilot_user.free_user_blocked?
        # first let's see if we have a limited user record for this user
        limited_user = find_by(user_id: copilot_user.id)

        # if we do, let's just return it, mmkay?
        if limited_user.present?
          GitHub.dogstats.increment("copilot.limited_user.find_for_copilot_user.exists")
          return limited_user
        end

        GitHub.dogstats.increment("copilot.limited_user.find_for_copilot_user.notfound")

        if !copilot_user.has_active_subscription? && !copilot_user.has_trial_subscription? && !copilot_user.has_cfe_access? && !copilot_user.has_cfb_access?
          # let's create the unsubscribed LimitedUser record and return it
          limited_user = with_write do
            GitHub.dogstats.increment("copilot.limited_user")
            LimitedUser.create(
              user_id: copilot_user.id,
            )
          end

          if limited_user.persisted?
            GitHub.dogstats.increment("copilot.limited_user.find_for_copilot_user.created")
            return limited_user
          end
        end
      end
    end

    sig { void }
    def destroy
      collect_metrics("copilot.limited_user.destroy") do
        super
      end
    end

    sig { returns(T::Boolean) }
    def subscribed?
      subscribed_at.present?
    end

    sig { returns(T::Boolean) }
    def subscribe
      collect_metrics("copilot.limited_user.subscribe") do
        with_write do
          update(subscribed_at: Time.now)
        end

        true
      end
    end

    sig { returns(T.nilable(Date)) }
    def reset_date
      collect_metrics("copilot.limited_user.reset_date") do
        return nil unless user.present?
        return nil unless subscribed?

        # we want to get the day of the month that the user subscribed
        day = subscribed_at.day

        # we want to get that same day for the next month
        next_month = Date.current.next_month
        reset_date = Date.new(next_month.year, next_month.month, day)

        reset_date
      end
    end

    # This returns the current quotas for all features
    # This is the free allotment for all users, not the individual user's quota
    sig { returns(T::Hash[String, Integer]) }
    def self.monthly_quotas
      quotas = Copilot.redis.hgetall(QUOTAS_KEY)

      converted_hash = T.let(Hash.new(0), T::Hash[String, Integer])
      # convert to integers
      quotas.keys.inject(converted_hash) do |acc, val|
        acc[val.to_s] = quotas[val].to_i
        acc
      end

      converted_hash
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
    # It will return -1 if the feature is invalid or the LimitedUser does not exist
    sig { params(feature: String).returns(Integer) }
    def feature_quota_remaining(feature:) # chat/completions/etc
      collect_metrics("copilot.limited_user.feature_quota_remaining") do
        return -1 unless user.present?
        return -1 unless subscribed?
        return -1 unless ALLOWED_FEATURES.include?(feature)

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
            current_max_quota = self.class.monthly_quotas[feature].to_i
            GitHub.logger.info("Current max quota", current_max_quota: current_max_quota)

            # so the quota can't be more than the max quota, so we need to set it to the lesser of the two
            new_quota = [quota, current_max_quota].min
            GitHub.logger.info("New quota", new_quota: new_quota)

            # now the new quota needs to be taken away from the max quota to get the new value
            updated_quota = current_max_quota - new_quota
            GitHub.logger.info("Updated quota", updated_quota: updated_quota)

            result = Copilot.redis.set(
              feature_count_key(feature),
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

    sig { params(feature: String).returns(T.nilable(String)) }
    def feature_count_key(feature)
      return nil unless user.present?

      "#{T.must(user).analytics_tracking_id}:#{feature}:#{Time.now.strftime("%Y_%m")}"
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
        monthly_quota = self.class.monthly_quotas[feature].to_i

        # we need to get the current count for the feature for the user
        value = Copilot.redis.get(feature_count_key(feature))

        # if it is null that means they haven't had any activity for the feature this month
        # so we will return that they have the full quota remaining
        return monthly_quota if value.nil?

        # let's convert the value to an integer
        used_quota = value.to_i

        # so, the quota remaining is the max quota minus the used quota
        monthly_quota - used_quota
      end
    end

    # This method will return the percentage of quota left for the user and the given feature
    sig { params(feature: String).returns(Float) }
    def get_feature_quota_percentage_remaining(feature) # chat/completions/etc
      collect_metrics("copilot.limited_user.get_feature_quota_percentage_remaining") do
        # this is the current max quota for the feature - this applies to all limited users
        monthly_quota = self.class.monthly_quotas[feature].to_f

        # we need to get the current count for the feature for the user
        value = Copilot.redis.get(feature_count_key(feature))

        # if it is null that means they haven't had any activity for the feature this month
        # so we will return that they have the full quota remaining
        return 100.0 if value.nil?

        # let's convert the value to an integer
        used_quota = value.to_f

        # so, the quota remaining is the max quota minus the used quota
        ((monthly_quota - used_quota) / monthly_quota) * 100
      end
    end
  end
end
