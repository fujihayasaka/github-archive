# typed: strict
# frozen_string_literal: true

module Copilot
  class QuotaCacheInvalidationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    locked_by timeout: 2.minutes, key: DEFAULT_LOCK_PROC
    exempt_from_tenant_context_requirement

    sig { params(user_id: T.nilable(Integer), customer_id: T.nilable(Integer), business_id: T.nilable(Integer)).void }
    def perform(user_id: nil, customer_id: nil, business_id: nil)
      return unless FeatureFlag.vexi.enabled?(:quota_cache_invalidation_job, default: false) || noop?

      GitHub.logger.info(
        "Starting QuotaCacheInvalidationJob",
        "gh.copilot.user_id" => user_id,
        "gh.copilot.customer_id" => customer_id,
        "gh.copilot.business_id" => business_id,
      )

      # what happens typically is that we will receive a customer_id and a user_id or a customer_id and a business_id.
      # so going down the customer_id path will take care of the other paths
      case
      when customer_id.present?
        invalidate_cache_for_customer(customer_id)
      when user_id.present?
        invalidate_cache_for_user(user_id)
      when business_id.present?
        invalidate_cache_for_business(business_id)
      else
        GitHub.logger.warn("QuotaCacheInvalidationJob called without user_id, customer_id, or business_id")
      end
    end

    private

    sig { params(user_id: Integer).void }
    def invalidate_cache_for_user(user_id)
      user = ::User.find_by(id: user_id)
      return unless user

      GitHub.logger.info(
        "Invalidating quota cache for user",
        "gh.copilot.user_id" => user_id,
        )

      Copilot::Instrumenter.instrument_copilot_limiter_bust_cache(
        tracking_id: user.analytics_tracking_id,
        cache_type: :USER_CACHE,
      )
    end

    sig { params(business_id: Integer).void }
    def invalidate_cache_for_business(business_id)
      business = ::Business.find_by(id: business_id)
      return unless business

      GitHub.logger.info(
        "Invalidating quota cache for business",
        "gh.copilot.business_id" => business_id,
        "gh.copilot.customer_id" => business.customer_id
      )
      invalidate_cache_for_customer(business.customer_id)
    end

    sig { params(customer_id: Integer).void }
    def invalidate_cache_for_customer(customer_id)
      customer = ::Customer.find_by(id: customer_id)
      return unless customer

      GitHub.logger.info(
        "Invalidating quota cache for customer",
        "gh.copilot.customer_id" => customer_id,
        "gh.copilot.business_id" => customer.business&.id
      )

      ::Copilot::Instrumenter.instrument_copilot_limiter_bust_cache(
        tracking_id: "",
        billable_customer_id: customer_id,
        cache_type: :USER_CACHE,
      )
    end

    sig { returns(T::Boolean) }
    def noop?
      FeatureFlag.vexi.enabled?(:quota_cache_invalidation_job_noop, default: false)
    end
  end
end
