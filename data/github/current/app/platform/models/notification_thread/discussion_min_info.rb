# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a discussion inside a notification thread.
  #
  # This implementation will focus on the discussion and not comments
  class DiscussionMinInfo
    include MinInfoTrait

    sig { returns(Discussion) }
    attr_reader :discussion

    sig { params(discussion: Discussion).void }
    def initialize(discussion:)
      @discussion = discussion
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.resolve(discussion.title)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      # Use #async_path_uri to avoid loading the repository and owner again
      discussion.async_path_uri.then do |uri|
        "#{GitHub.url}#{uri}"
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      discussion.async_user.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      discussion.async_user
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill(TruncatedBody.new(discussion.body.to_s).to_s)
    end
  end
end
