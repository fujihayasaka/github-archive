# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # Find invitations between user -> repo pairs, or `nil` if no invitation exists.
    class RepositoryInvitation < Platform::Loader
      def self.load(user, repository)
        self.for(user).load(repository.id)
      end

      def initialize(user)
        @user = user
      end

      def fetch(repository_ids)
        invitations = ::RepositoryInvitation.where(invitee: @user, repository: repository_ids)
        # Return `id => invitation` pair; the base class will send `nil` for any missing invitation
        invitations.index_by(&:repository_id)
      end
    end
  end
end
