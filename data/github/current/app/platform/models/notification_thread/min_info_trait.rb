# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Interface for all the MinInfo classes
  # Any new class needs to implement this interface
  module MinInfoTrait
    extend T::Helpers
    abstract!

    sig { abstract.returns(Promise[T.nilable(String)]) }
    def async_title; end

    sig { abstract.returns(Promise[T.nilable(String)]) }
    def async_url; end

    sig { abstract.returns(Promise[T::Array[User]]) }
    def async_recent_participants; end

    sig { abstract.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author; end

    sig { abstract.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body; end

    sig { overridable.returns(Promise[T.nilable(T::Boolean)]) }
    def async_pull_request?
      Promise.new.fulfill(false)
    end

    sig { overridable.returns(Promise[T.nilable(String)]) }
    def async_check_suite_conclusion
      Promise.new.fulfill(nil)
    end
  end
end
