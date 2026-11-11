# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a memex_project inside a notification thread.
  #
  # This implementation will focus on the memex_project and not status updates
  class MemexProjectMinInfo
    include MinInfoTrait

    sig { returns(MemexProject) }
    attr_reader :memex_project

    sig { params(memex_project: MemexProject).void }
    def initialize(memex_project:)
      @memex_project = memex_project
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.resolve(memex_project.title)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      memex_project.async_permalink
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      memex_project.async_creator.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      memex_project.async_creator
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill(TruncatedBody.new(memex_project.description.to_s).to_s)
    end
  end
end
