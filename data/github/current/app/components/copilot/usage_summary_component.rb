# typed: strict
# frozen_string_literal: true

module Copilot
  class UsageSummaryComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = copilot_user
      @percent_used = T.let("0.0", String)
      @remaining = T.let("0", String)
      @entitlement = T.let("0", String)
      @overage_count = T.let("0", String)
      @timestamp_utc = T.let(Time.now.utc, Time)
      @emphasis = T.let(:success_emphasis, Symbol)
      @used = T.let("0", String)

      if copilot_user.quota_snapshots["premium_interactions"]
        @percent_used = number_with_precision(100 - T.must(copilot_user.quota_snapshots["premium_interactions"])[:percent_remaining], precision: 1)
        @remaining = number_with_precision(T.must(copilot_user.quota_snapshots["premium_interactions"])[:remaining], precision: 0)
        @entitlement = number_with_precision(T.must(copilot_user.quota_snapshots["premium_interactions"])[:entitlement], precision: 0)
        @overage_count = number_with_precision(T.must(copilot_user.quota_snapshots["premium_interactions"])[:overage_count], precision: 0)
        @timestamp_utc = T.must(copilot_user.quota_snapshots["premium_interactions"])[:timestamp_utc]
        used = T.must(copilot_user.quota_snapshots["premium_interactions"])[:entitlement] - T.must(copilot_user.quota_snapshots["premium_interactions"])[:remaining]
        used = 0 if used.negative?
        used = T.must(copilot_user.quota_snapshots["premium_interactions"])[:entitlement] if used > T.must(copilot_user.quota_snapshots["premium_interactions"])[:entitlement]
        @used = number_with_precision(used, precision: 0)

        @emphasis = :attention_emphasis if @percent_used.to_f >= 80.0 && @percent_used.to_f < 100.0
        @emphasis = :danger_emphasis if @percent_used.to_f >= 100.0
      end
    end

    sig { returns(T::Boolean) }
    def render?
      return true if current_user.feature_flag_enabled?(:show_copilot_usage_quota, default: false) && @copilot_user.consumptive_user?
      false
    end

    sig { returns(T::Boolean) }
    def render_numbers?
      current_user.feature_flag_enabled?(:show_copilot_usage_quota_numbers, default: false)
    end

    sig { returns(String) }
    def pluralized_remaining
      return "requests" if @remaining.to_i > 1 || @remaining.to_i.zero?
      "request"
    end

    sig { returns(String) }
    def pluralized_overage
      return "requests" if @overage_count.to_i > 1 || @overage_count.to_i.zero?
      "request"
    end
  end
end
