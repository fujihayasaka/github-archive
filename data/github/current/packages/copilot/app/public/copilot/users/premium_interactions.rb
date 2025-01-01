# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module PremiumInteractions
      extend T::Helpers
      include Api::Internal::Twirp::Copilot::Helpers

      abstract!

      include Copilot::Users::Signatures
      include GitHub::Memoizer

      ALLOWED_FREE_FEATURES = T.let(%w[chat completions], T::Array[String])
      ALLOWED_PREMIUM_FEATURES = T.let(%w[premium_interactions], T::Array[String])

      sig { override.returns(T::Boolean) }
      memoize def consumptive_user?
        copilot_authorizer_object_no_snippy.has_premium_interactions?
      end

      sig { override.returns(Date) }
      memoize def quota_reset_date
        return T.must(limited_user).reset_date if has_limited_access?

        # for all other users, the reset date is the first day of the next month
        Date.current.beginning_of_month.next_month
      end

      sig { returns(T.any(Time, Date)) }
      memoize def quota_reset_date_utc
        return T.must(limited_user).reset_date if has_limited_access?
        Time.current.utc.next_month.beginning_of_month
      end

      sig { override.returns(T::Boolean) }
      memoize def has_completions_quota_remaining?
        return true unless has_limited_access?

        limited_user = Copilot::LimitedUser.find_by(user: user_object)
        return false unless limited_user.present?

        limited_user.feature_allowed?(feature: "completions")
      end

      sig { override.returns(T::Boolean) }
      memoize def has_chat_quota_remaining?
        if has_limited_access?
          return false unless limited_user.present?
          return T.must(limited_user).feature_allowed?(feature: "chat")
        end
        # if they aren't a limited user, we are really checking
        # whether they have premium quota remaining
        true
      end

      sig { override.returns(T::Array[CopilotQuotaDetail]) }
      memoize def quota_details
        return [] unless has_limited_access?
        return [] unless limited_user.present?

        T.must(limited_user).quotas_remaining.map do |feature, remaining|
          feature_monthly_quota = Copilot::Quotas.monthly_quotas[feature].to_f
          {
            feature: feature,
            quota: remaining,
            percentage: (remaining.to_f / feature_monthly_quota) * 100.0,
          }
        end
      end

      sig { override.params(feature: String).returns(Float) }
      def quota_percentage_remaining(feature:)
        (quota_snapshots.dig(feature, :percent_remaining) || 0).to_f
      end

      sig { override.params(feature: String).returns(Float) }
      def quota_feature_entitlement(feature:)
        (quota_snapshots.dig(feature, :entitlement) || 0).to_f
      end

      sig { override.params(feature: String).returns(Float) }
      def quota_feature_overage_count(feature:)
        (quota_snapshots.dig(feature, :overage_count) || 0).to_f
      end

      sig { override.returns(T::Hash[String, QuotaSnapshot]) }
      memoize def quota_snapshots
        load_quota_snapshots.each_with_object({}) do |snapshot, hash|
          # use the snapshot without the quota_id
          hash[snapshot[:quota_id]] = snapshot
        end
      end

      sig do
        params(
          feature: String,
          quota: Float,
        ).returns(GitHub::Result)
      end
      def set_quota_feature_entitlement(feature:, quota:)
        collect_metrics("copilot.premium_interactions.set_quota_remaining") do
          GitHub.logger.with_named_tags({
            "code.namespace": "Copilot::Users::PremiumInteractions",
            "code.function": "set_quota_feature_entitlement",
            "gh.user.analytics_tracking_id": user_object.analytics_tracking_id,
            "gh.copilot_limiter.feature": feature,
            "gh.copilot_limiter.quota": quota,
          }) do
            GitHub::Result.new do
              Kernel.raise "User not found" unless user_object.present?

              if has_limited_access?
                unless ALLOWED_FREE_FEATURES.include?(feature)
                  GitHub.logger.info("Invalid feature for Copilot Free user")
                  Kernel.raise "Invalid feature for Copilot Free user: #{feature}"
                end

                unless limited_user.present? && T.must(limited_user).subscribed?
                  GitHub.logger.info("User not subscribed or limited user not present")
                  Kernel.raise "User not subscribed to Copilot Free"
                end
              end

              if consumptive_user?
                unless ALLOWED_PREMIUM_FEATURES.include?(feature)
                  GitHub.logger.info("Invalid feature for Copilot consumptive user")
                  Kernel.raise "Invalid feature for consumptive user: #{feature}"
                end
              end

              result = CopilotLimiter::Twirp.quota_client.set_quota(
                copilot_tracking_id: user_object.analytics_tracking_id,
                feature: feature,
                quota: quota,
                twirp_access_type: twirp_access_type(copilot_authorizer_object_no_snippy.access_type),
              )
              GitHub.logger.info("Quota set in twirp")
              copilot_user_object.invalidate_quota_cache!

              return GitHub::Result.new { result }
            end
          end
        end
      end

      sig { params(feature: String).returns(T::Boolean) }
      def can_access_feature?(feature)
        if limited_user&.subscribed?
          return ALLOWED_FREE_FEATURES.include?(feature)
        end
        if consumptive_user?
          return ALLOWED_PREMIUM_FEATURES.include?(feature)
        end
        false
      end

      sig { returns(T::Hash[T.untyped, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
      def get_consumptive_user
        GitHub.logger.with_named_tags({
          "code.function": "get_consumptive_user",
          "code.namespace": "Copilot::Users::PremiumInteractions",
          "gh.user.analytics_tracking_id": user_object.analytics_tracking_id,
        }) do
          GitHub.logger.info("Getting consumptive user")

          # Call the Limiter service to get the consumptive user
          CopilotLimiter::Twirp.quota_client.get_consumptive_user(
            copilot_tracking_id: user_object.analytics_tracking_id,
          )
        end
      end

      private

      sig { returns(String) }
      def cache_key
        "premium_interactions:#{user_object.analytics_tracking_id}"
      end

      sig { returns(T::Array[QuotaSnapshot]) }
      memoize def load_quota_snapshots
        GitHub.dogstats.distribution_time("copilot.user.load_quota_snapshots.latency") do
          values = GitHub.cache.fetch(
            cache_key,
            ttl: 30.seconds,
            stats_key: "copilot.user.load_quota_snapshots.quota_cache",
            force: Rails.env.development?,
          ) do
            return [] unless user_object.present?

            GitHub.logger.with_named_tags({
              "code.function": "load_quota_snapshots",
              "code.namespace": "Copilot::Users::PremiumInteractions",
              "gh.user.analytics_tracking_id": user_object.analytics_tracking_id,
            }) do
              GitHub.dogstats.increment("copilot.user.load_quota_snapshots.cache_miss", tags: { access_type: copilot_authorizer_object_no_snippy.access_type })

              # this will get the free quota from twirp
              return CopilotLimiter::Twirp.quota_client.get_quota_remaining(
                copilot_tracking_id: user_object.analytics_tracking_id,
                twirp_access_type: twirp_access_type(copilot_authorizer_object_no_snippy.access_type),
              ).map do |feature, quota|
                {
                  entitlement: quota[:entitlement].to_i,
                  overage_count: quota[:overage_count].to_i,
                  overage_permitted: quota[:overage_permitted],
                  percent_remaining: quota[:percent_remaining].to_f,
                  quota_id: feature.to_s,
                  quota_remaining: quota[:quota_remaining].to_f,
                  remaining: quota[:remaining].to_i,
                  unlimited: quota[:unlimited],
                  timestamp_utc: Time.now.utc,
                }
              end
            end
          end
          values
        end
      end
    end
  end
end
