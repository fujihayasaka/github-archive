# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for an advisory credit inside a notification thread.
  class AdvisoryCreditMinInfo
    include MinInfoTrait

    sig { returns(AdvisoryCredit) }
    attr_reader :advisory_credit

    sig { params(advisory_credit: AdvisoryCredit).void }
    def initialize(advisory_credit:)
      @advisory_credit = advisory_credit
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.new.fulfill(advisory_credit.notification_summary_title)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      T.cast(advisory_credit.async_permalink, Promise[T.nilable(String)])
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      advisory_credit.async_notifications_author.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      advisory_credit.async_notifications_author
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      T.cast(advisory_credit.async_notification_summary_body, Promise[T.nilable(String)])
    end
  end
end
