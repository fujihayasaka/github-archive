# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a gist inside a notification thread.
  #
  # This implementation will focus on the gist and not mentions or comments
  class GistMinInfo
    include MinInfoTrait

    sig { returns(Gist) }
    attr_reader :gist

    sig { params(gist: Gist).void }
    def initialize(gist:)
      @gist = gist
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.resolve(gist.title)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      gist.async_user.then do |_|
        gist.permalink
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      gist.async_user.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      gist.async_user
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill(TruncatedBody.new(gist.description.to_s).to_s)
    end
  end
end
