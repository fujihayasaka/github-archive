# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a member feature request notification inside a notification thread.
  class MemberFeatureRequestMinInfo
    include MinInfoTrait

    sig { returns(MemberFeatureRequest::Notification) }
    attr_reader :request

    sig { params(request: MemberFeatureRequest::Notification).void }
    def initialize(request:)
      @request = request
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      T.cast(request.async_body, Promise[T.nilable(String)])
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      T.cast(request.async_permalink, Promise[T.nilable(String)])
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      request.async_user.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      request.async_user
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      T.cast(request.async_body, Promise[T.nilable(String)])
    end
  end
end
