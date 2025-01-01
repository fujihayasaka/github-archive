# typed: true
# frozen_string_literal: true

class MobilePushNotificationSetting < ApplicationRecord::Domain::Notifications

  class NotifydError < StandardError
  end

  self.utc_datetime_columns = %i[created_at updated_at]

  belongs_to :user
  after_commit :save_notifyd_settings

  sig { returns(T::Boolean) }
  def direct_mentions?
    self.direct_mention
  end

  sig { returns(T::Boolean) }
  def assignments?
    self.assignment
  end

  sig { returns(T::Boolean) }
  def review_requests?
    self.review_requested
  end

  sig { returns(T::Boolean) }
  def deployment_requests?
    self.deployment_request
  end

  sig { returns(T::Boolean) }
  def pull_request_reviews?
    self.pull_request_review
  end

  sig { returns(T::Boolean) }
  def ci_activity
    notifyd_settings.actions.push
  end
  alias ci_activity? ci_activity

  sig { returns(T::Boolean) }
  def ci_failed_only
    notifyd_settings.actions.failures
  end
  alias ci_failed_only? ci_failed_only

  sig { params(val: T::Boolean).void }
  def ci_activity=(val)
    @notifyd_settings = Notifications::Settings::MobileSettings.new(
      actions: Notifications::Settings::MobileActionsSettings.new(
        push: val,
        failures: notifyd_settings.actions.failures,
      ),
      releases: notifyd_settings.releases,
    )
  end

  sig { params(val: T::Boolean).void }
  def ci_failed_only=(val)
    @notifyd_settings = Notifications::Settings::MobileSettings.new(
      actions: Notifications::Settings::MobileActionsSettings.new(
        push: notifyd_settings.actions.push,
        failures: val,
      ),
      releases: notifyd_settings.releases,
    )
  end

  sig { returns(T::Boolean) }
  def releases
    notifyd_settings.releases.push
  end
  alias releases? releases

  sig { params(val: T::Boolean).void }
  def releases=(val)
    @notifyd_settings = Notifications::Settings::MobileSettings.new(
      actions: notifyd_settings.actions,
      releases: Notifications::Settings::MobileReleasesSettings.new(push: val),
    )
  end

  def reload
    @notifyd_settings = nil
    super
  end

  private

  sig { returns(Notifications::Settings::MobileSettings) }
  def notifyd_settings
    @notifyd_settings ||= Notifications::Settings.mobile(T.must(user))
    raise NotifydError unless @notifyd_settings
    @notifyd_settings
  end

  def save_notifyd_settings
    return unless user

    # We only want to save notifyd settings if they have changed,
    # and having loaded them is a requisite for that.
    return unless @notifyd_settings

    Notifications::Settings::set_mobile(T.must(user), @notifyd_settings)
  end
end
