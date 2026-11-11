# typed: strict
# frozen_string_literal: true

#
# Stafftools component for displaying cached consumptive user data from the CopilotLimiter service.
# This component safely fetches and displays quota information for debugging purposes.
#
class Stafftools::Copilot::CachedConsumptiveUserComponent < ApplicationComponent
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  attr_reader :consumptive_user

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(T::Boolean) }
  def render?
    FeatureFlag.vexi.enabled?("copilot_show_cached_consumptive_user", @copilot_user.user_object, default: false)
  end

  sig { params(copilot_user: Copilot::User).void }
  def initialize(copilot_user)
    @copilot_user = copilot_user

    unless copilot_user.user_object.present?
      @consumptive_user = {}
      return
    end

    tracking_id = copilot_user.user_object.analytics_tracking_id
    if tracking_id.blank?
      @consumptive_user = {}
      return
    end

    @consumptive_user = T.let(
      fetch_consumptive_user(tracking_id),
      T.nilable(T::Hash[Symbol, T.untyped])
    )
  end

  private

  sig { params(tracking_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def fetch_consumptive_user(tracking_id)
    response = CopilotLimiter::Twirp.quota_client.get_consumptive_user(copilot_tracking_id: tracking_id)

    return nil if response.empty?

    response.dup.tap do |result|
      result[:reset_date] = format_reset_date(result[:reset_date]) if result[:reset_date]
    end
  rescue TwirpHelper::TwirpError => e
    # Log the error but don't crash the component
    GitHub.logger.error("Error fetching consumptive user data", {
      "code.function": "fetch_consumptive_user",
      "code.namespace": self.class.name,
      "error.message": e.message,
      "error.class": e.class.name
    })
    {}
  end

  sig { params(reset_date: T.untyped).returns(T::Hash[Symbol, Integer]) }
  def format_reset_date(reset_date) = { year: reset_date.year, month: reset_date.month, day: reset_date.day }
end
