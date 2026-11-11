# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a repository dependabot alerts thread inside a notification thread.
  #
  # This doesn't include events associated to the thread instance
  class RepositoryDependabotAlertsThreadMinInfo
    include MinInfoTrait

    sig { returns(VulnerabilityAlertingEvent::VulnerableRepositoryNotification) }
    attr_reader :notification

    sig { params(repository: T.untyped, dependabot_alert: RepositoryDependabotAlertsThread).void }
    def initialize(repository:, dependabot_alert:)
      alert = Struct.new(:id, :vulnerability, :created_at).new(dependabot_alert.id, dependabot_alert, Time.now)
      @notification = VulnerabilityAlertingEvent::VulnerableRepositoryNotification.new(repository, alert)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.new.fulfill(notification.notifications_title)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      notification.repository.async_owner.then do
        notification.permalink
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      Promise.new.fulfill([notification.notifications_author])
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      Promise.new.fulfill(notification.notifications_author)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.resolve(notification.body)
    end
  end
end
