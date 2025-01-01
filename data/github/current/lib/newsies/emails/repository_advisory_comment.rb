# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class RepositoryAdvisoryComment < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::RepositoryAdvisoryComment)
      end

      def in_reply_to
        repository_advisory&.message_id
      end

      def subject
        "Re: [#{repository.name_with_display_owner}] #{title} (#{repository_advisory&.ghsa_id})"
      end

      def title
        repository_advisory&.get_title(settings_user)
      end

      def reason_in_words
        "You are receiving this because you are either an administrator on #{repository.name_with_display_owner}, or a collaborator on #{repository_advisory&.ghsa_id}."
      end

      private

      sig { returns(T.nilable(::RepositoryAdvisory)) }
      def repository_advisory
        T.let(comment, ::RepositoryAdvisoryComment).repository_advisory
      end
    end
  end
end
