# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class Discussion < Newsies::Emails::Message
      extend T::Sig

      sig { returns ::Discussion }
      def discussion
        comment
      end

      sig { params(comment: T.untyped).returns(T::Boolean) }
      def self.matches?(comment)
        comment.is_a?(::Discussion)
      end

      sig { returns String }
      def subject
        "[#{owner}] #{discussion.title} (Discussion ##{discussion.number})"
      end

      private

      def owner
        repository&.organization_discussion.present? ? repository.organization.safe_profile_name : repository.name_with_display_owner
      end
    end
  end
end
