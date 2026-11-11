# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Void implementation of the MinInfoTrait. It always returns nil or empty values
  class NullMinInfo
    include MinInfoTrait

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.new.fulfill(nil)
    end

    sig { override.returns(Promise[T.nilable(T::Boolean)]) }
    def async_pull_request?
      Promise.new.fulfill(nil)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      Promise.new.fulfill(nil)
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      Promise.new.fulfill([])
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      Promise.new.fulfill(nil)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill(nil)
    end
  end
end
