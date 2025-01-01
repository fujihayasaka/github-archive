# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class RepositoryInvitation < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::RepositoryInvitation)
      end

      # RepositoryInvitation emails are handled by RepositoryMailer
      # so they should not be delivered by the newsies system.
      #
      # The job that invokes those emails is RepositoryCollabInvitationJob
      def deliverable?
        false
      end
    end
  end
end
