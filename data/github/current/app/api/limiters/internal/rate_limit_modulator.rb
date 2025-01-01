# typed: true
# frozen_string_literal: true

module Api::Limiters::Internal::RateLimitModulator
  extend T::Helpers

  requires_ancestor { GitHub::Limiter }

  # WARNING: This mixin should only be applied to limiters that have been explicitly approved by the API team.
  # Unapproved use may lead to unintended behavior if ever we decide to employ this feature.
  #
  # The modulator serves as a fail-safe mechanism for high-threshold limiters, designed with Proxima's capacity in mind.
  # It enables dynamic adjustments to rate limit thresholds in real-time, allowing us to scale limits globally based on
  # the utilization and load of unicorn workers.


  # feature flags for modulation
  DECREASE_LIMIT_TIER_1 = :rlm_decrease_limit_tier_1
  DECREASE_LIMIT_TIER_2 = :rlm_decrease_limit_tier_2
  INCREASE_LIMIT_TIER_1 = :rlm_increase_limit_tier_1
  INCREASE_LIMIT_TIER_2 = :rlm_increase_limit_tier_2

  # Map feature flags to their respective multipliers
  FEATURE_FLAG_MULTIPLIERS = {
    DECREASE_LIMIT_TIER_1 => 0.75,
    DECREASE_LIMIT_TIER_2 => 0.5,
    INCREASE_LIMIT_TIER_1 => 1.5,
    INCREASE_LIMIT_TIER_2 => 2.0
  }.freeze

  # Ensuring that only approved limiters can include this module.
  sig { params(base: T.class_of(GitHub::Limiter)).void }
  def self.included(base)
    raise "The RateLimitModulator can only be included for approved limiters" unless approved_limiter?(base)
  end

  # Helper method to check if the limiter is approved.
  sig { params(klass: T.class_of(GitHub::Limiter)).returns(T::Boolean) }
  def self.approved_limiter?(klass)
    [
      Api::Limiters::Internal::AuthenticationFingerprintByPath,
      Api::Limiters::Internal::ConcurrentAuthenticationFingerprint,
      Api::Limiters::Internal::ElapsedTimeByAuthenticationFingerprint,
      Api::Limiters::Internal::TwirpElapsedTimeByTwirpClient,
      Api::Limiters::Internal::TwirpRequestCountByClientAndPath
    ].include?(klass)
  end

  # Public: Override the default rate limit for a modulated/adjusted limit.
  #
  # request - Rack::Request instance.
  sig { params(request: Rack::Request).returns(GitHub::Limiter::State) }
  def start(request)
    @limit = modulate_limit!(@limit) if modulation_enabled?
    super(request)
  end

  private

  # Private: Checks if the modulation feature is enabled.
  sig { returns(T::Boolean) }
  def modulation_enabled?
    !!(GitHub.multi_tenant_enterprise? && GitHub.flipper[:rate_limit_modulation].enabled?)
  end

  # Private: Adjust limits based on feature flag precedence.
  #
  # Only one feature flag should be enabled at a time.
  sig { params(base_limit: Integer).returns(Integer) }
  def modulate_limit!(base_limit)
    return @modulated_limit if @modulated_limit

    FEATURE_FLAG_MULTIPLIERS.each do |flag, multiplier|
      if GitHub.flipper[flag].enabled?
        @modulated_limit = (base_limit * multiplier).to_i
        break
      end
    end
    @modulated_limit ||= base_limit # Return the base limit if no modulation is applied.
  end
end
