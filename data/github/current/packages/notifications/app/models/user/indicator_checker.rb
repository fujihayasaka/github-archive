# typed: true
# frozen_string_literal: true

class User::IndicatorChecker
  include GitHub::Memoizer

  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Public: Gets and fills the cache for the user's mode, if it's an available mode.
  #
  # user       - A User.
  #
  # Returns a Symbol mode.
  memoize def mode
    check_mode
  end

  private

  def check_mode
    if user && FeatureFlag.vexi.enabled?(:notifications_indicator_metrics, user, default: false)
      response = user_mode
      GitHub.dogstats.increment("notifications.indicator_checker.success", tags: ["action:check_mode", "user_mode:#{response}"])
      log_to_hydro(response)

      response
    else
      return :none if user.nil?
      global_response = GitHub.newsies.web.exist(user, unread: true)
      return :unavailable if global_response.failed?
      return :global if global_response.value?
      return :disabled unless Notifications::Settings.web?(user)
      :none
    end
  end

  memoize def unread_notifications
    GitHub.newsies.web.exist(user, unread: true)
  end

  memoize def count_unread_notifications
    GitHub.newsies.web.count(user, unread: true)
  end

  def web_notifications_enabled?
    Notifications::Settings.web?(user)
  end

  def user_mode
    return :none if user.nil?
    return :unavailable if unread_notifications.failed?
    return :global if unread_notifications.value?
    return :disabled unless web_notifications_enabled?
    :none
  end

  def log_to_hydro(response)
    GlobalInstrumenter.instrument("notifications.telemetry", {
      user: user,
      event: "indicator_checker",
      metadata: {
        "web_notifications_enabled" => web_notifications_enabled?.to_s,
        "unread_notifications" => unread_notifications.value?.to_s,
        "count_unread_notifications" => count_unread_notifications.to_s,
        "indicator_mode" => response.to_s,
      },
    })
  end
end
