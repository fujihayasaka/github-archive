# typed: true
# frozen_string_literal: true

class MobilePushNotificationSetting < ApplicationRecord::Domain::Notifications
  extend T::Sig

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
    notifyd_settings.ci_activity
  end
  alias ci_activity? ci_activity

  sig { returns(T::Boolean) }
  def ci_failed_only
    notifyd_settings.ci_failed_only
  end
  alias ci_failed_only? ci_failed_only

  sig { params(val: T::Boolean).returns(T::Boolean) }
  def ci_activity=(val)
    notifyd_settings.ci_activity = val
  end

  sig { params(val: T::Boolean).returns(T::Boolean) }
  def ci_failed_only=(val)
    notifyd_settings.ci_failed_only = val
  end

  sig { returns(T::Boolean) }
  def releases
    notifyd_settings.releases
  end
  alias releases? releases

  sig { params(val: T::Boolean).returns(T::Boolean) }
  def releases=(val)
    notifyd_settings.releases = val
  end

  def reload
    @notifyd_settings = nil
    super
  end

  private

  sig { returns(Notifyd::MobilePushSettings) }
  def notifyd_settings
    flags = Notifyd::Flags.new(user)

    return Notifyd::MobilePushSettings.default unless user
    return Notifyd::MobilePushSettings.default unless flags.push_ci_activity? || flags.push_releases?

    @notifyd_settings ||= Notifyd::MobilePushSettingsStore.new(user: T.must(user)).get
  end

  def save_notifyd_settings
    return unless user

    Notifyd::MobilePushSettingsStore
      .new(user: T.must(user))
      .save(settings: notifyd_settings)
  end
end
