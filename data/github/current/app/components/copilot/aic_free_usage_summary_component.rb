# typed: strict
# frozen_string_literal: true

module Copilot
  class AicFreeUsageSummaryComponent < ApplicationComponent
    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = copilot_user

      @limited_user_chat_used_percentage = T.let(0.0, Float)
      @limited_user_suggestions_used_percentage = T.let(0.0, Float)

      # Upgrade CTA state
      @show_upgrade_cta = T.let(false, T::Boolean)
      @show_persistent_upgrade_cta = T.let(false, T::Boolean)
      @is_free_user = T.let(@copilot_user.has_limited_access?, T::Boolean)

      @usage_banner_scheme = T.let(nil, T.nilable(Symbol))
      @usage_banner_message = T.let(nil, T.nilable(String))

      return unless @copilot_user.has_cfi_access?

      compute_limited_user_credit_quota
      compute_free_usage_banner
    end

    sig { returns(T::Boolean) }
    def render?
      @copilot_user.has_cfi_access? && @is_free_user
    end

    private

    sig { void }
    def compute_limited_user_credit_quota
      compute_chat_percent_used
      compute_suggestions_percent_used
    end

    sig { void }
    def compute_chat_percent_used
      chat_snapshot = @copilot_user.quota_snapshots["chat"] || {}
      percent_remaining = chat_snapshot.fetch(:percent_remaining, 100.0)

      @limited_user_chat_used_percentage = Copilot::QuotaDataHelper.format_percentage_used(100.0 - percent_remaining)
    end

    sig { void }
    def compute_suggestions_percent_used
      suggestions_snapshot = @copilot_user.quota_snapshots["completions"] || {}
      percent_remaining = suggestions_snapshot.fetch(:percent_remaining, 100.0)

      @limited_user_suggestions_used_percentage = Copilot::QuotaDataHelper.format_percentage_used(100.0 - percent_remaining)
    end

    sig { void }
    def compute_free_usage_banner
      if free_usage_exhausted?
        @usage_banner_scheme = :danger
        @usage_banner_message = "You've run out of your included usage with the free plan. Limit resets on #{Copilot::QuotaDataHelper.short_usage_reset_date(@copilot_user, time_zone: user_time_zone)}."
        @show_upgrade_cta = !@copilot_user.cfi_paid_plan_upgrade_restricted?
      else
        @show_persistent_upgrade_cta = !@copilot_user.cfi_paid_plan_upgrade_restricted?
      end
    end

    sig { returns(T::Boolean) }
    def free_usage_exhausted?
      @limited_user_chat_used_percentage >= 100.0 && @limited_user_suggestions_used_percentage >= 100.0
    end

    sig { returns(ActiveSupport::TimeZone) }
    def user_time_zone
      @copilot_user.user_object.time_zone
    end
  end
end
