# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a repository advisory inside a notification thread.
  #
  # This doesn't include comments or events associated to the repository advisory instance
  class RepositoryAdvisoryMinInfo
    include MinInfoTrait

    sig { returns(::User) }
    attr_reader :user

    sig { returns(RepositoryAdvisory) }
    attr_reader :repository_advisory

    sig { params(user: ::User, repository_advisory: RepositoryAdvisory).void }
    def initialize(user:, repository_advisory:)
      @user = user
      @repository_advisory = repository_advisory
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      repository_advisory.async_get_title(user)
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      T.cast(repository_advisory.async_permalink, Promise[T.nilable(String)])
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      repository_advisory.async_author.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      repository_advisory.async_author
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      repository_advisory.async_get_description(user)
    end
  end
end
