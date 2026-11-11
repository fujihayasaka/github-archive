# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a release inside a notification thread.
  #
  # This implementation will focus on the release
  class ReleaseMinInfo
    include MinInfoTrait

    sig { returns(Release) }
    attr_reader :release

    sig { params(release: Release).void }
    def initialize(release:)
      @release = release
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.resolve(release.display_name)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      release.async_repository.then do |_|
        release.permalink
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      release.async_user.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      release.async_user
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill(TruncatedBody.new(release.display_body.to_s).to_s)
    end
  end
end
