# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a commit inside a notification thread.
  #
  # This implementation will focus on the commit and not mentions or comments
  class CommitMinInfo
    include MinInfoTrait

    sig { returns(Commit) }
    attr_reader :commit

    sig { params(commit: Commit).void }
    def initialize(commit:)
      @commit = commit
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.resolve(commit.short_message_text)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      commit.async_path_uri.then do |uri|
        "#{GitHub.url}#{uri}"
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      commit.async_user.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      commit.async_user
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill(TruncatedBody.new(commit.message_body_text.to_s).to_s)
    end
  end
end
