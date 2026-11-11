# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Provide the minimal information for a repository invitation inside a notification thread.
  class RepositoryInvitationMinInfo
    include MinInfoTrait

    sig { returns(RepositoryInvitation) }
    attr_reader :repository_invitation

    sig { params(repository_invitation: RepositoryInvitation).void }
    def initialize(repository_invitation:)
      @repository_invitation = repository_invitation
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_title
      Promise.all([
        repository_invitation.async_inviter,
        repository_invitation.async_repository,
      ]).then do |_, repository|
        repository&.async_owner.then do
          repository_invitation.summary
        end
      end
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_url
      repository_invitation.async_repository.then do |repository|
        repository&.async_owner.then do
          repository_invitation.permalink
        end
      end
    end

    sig { override.returns(Promise[T::Array[User]]) }
    def async_recent_participants
      repository_invitation.async_inviter.then { |user| [user].compact }
    end

    sig { override.returns(Promise[T.nilable(User)]) }
    def async_summary_item_author
      repository_invitation.async_inviter
    end

    sig { override.returns(Promise[T.nilable(String)]) }
    def async_summary_item_body
      Promise.new.fulfill("")
    end
  end
end
