# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class DiscussionCommentRenderer
      extend T::Sig

      sig { params(discussion_comment: ::DiscussionComment, discussion: ::Discussion, author: Author).void }
      def initialize(discussion_comment:, discussion:, author:)
        @discussion_comment = discussion_comment
        @discussion = discussion
        @author = author
      end

      sig { returns(Notifyd::Proto::Layouts::Mobile::Basic) }
      def render
        title = TitleMention.new(author: author)
        subtitle = Subtitle.new(repository: discussion.repository, number: discussion.number)
        thread = DiscussionThread.new(discussion: discussion)

        Notifyd::Proto::Layouts::Mobile::Basic.new(
          title: title.to_s,
          subtitle: subtitle.to_s,
          body: discussion_comment.body,
          url: discussion_comment.permalink,
          avatar_url: author.avatar_url,
          author_profile_name: author.profile_name,
          author_username: author.username,
          thread_id: thread.id,
          thread_type: thread.type,
        )
      end

      private

      sig { returns(::DiscussionComment) }
      attr_reader :discussion_comment
      sig { returns(::Discussion) }
      attr_reader :discussion
      sig { returns(Author) }
      attr_reader :author
    end
  end
end
