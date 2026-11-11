# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a security advisory inside a notification thread.
  #
  # This doesn't include events associated to the security advisory instance
  class SecurityAdvisoryMinInfo
    include MinInfoTrait

    sig { returns(VulnerabilityAlertingEvent::SecurityAdvisoryNotification) }
    attr_reader :notification

    sig { params(list: T.untyped, security_advisory: SecurityAdvisory).void }
    def initialize(list:, security_advisory:)
      alert = Struct.new(:id, :vulnerability, :created_at).new(security_advisory.id, security_advisory, security_advisory.created_at)
      @notification = VulnerabilityAlertingEvent::SecurityAdvisoryNotification.new(list, alert)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      # the title uses information from version ranges, so we load them async first
      # to avoid N+1 queries if possible
      notification.security_advisory.async_vulnerable_version_ranges.then do
        notification.notifications_title
      end
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      Promise.resolve(notification.permalink)
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
