# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for an issue inside a notification thread.
  #
  # This implementation will focus on the issue and not comments or other events
  class IssueMinInfo
    include MinInfoTrait

    sig { returns(Issue) }
    attr_reader :issue

    sig { params(issue: Issue).void }
    def initialize(issue:)
      @issue = issue
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.resolve(issue.title)
    end

    sig { override.returns(Promise[T.nilable(T::Boolean)]) }
    def async_pull_request?
      Promise.resolve(issue.pull_request_id.present?)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      # Use #async_path_uri to avoid loading the repository and pull_request again
      issue.async_path_uri.then do |uri|
        "#{GitHub.url}#{uri}"
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      issue.async_user.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      issue.async_user
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill(TruncatedBody.new(issue.body.to_s).to_s)
    end
  end
end
