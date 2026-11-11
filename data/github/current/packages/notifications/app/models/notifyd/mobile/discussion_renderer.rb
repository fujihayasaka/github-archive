# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class DiscussionRenderer

      sig { params(discussion: ::Discussion, author: Author).void }
      def initialize(discussion:, author:)
        @discussion = discussion
        @author = author
      end

      sig { returns(Notifyd::Proto::Layouts::Mobile::Basic) }
      def render
        thread = DiscussionThread.new(discussion: discussion)
        title = TitleMention.new(author: author)
        subtitle = Subtitle.new(repository: discussion.repository, number: discussion.number)

        Notifyd::Proto::Layouts::Mobile::Basic.new(
          title: title.to_s,
          subtitle: subtitle.to_s,
          body: discussion.body,
          url: discussion.permalink,
          avatar_url: author.avatar_url,
          author_profile_name: author.profile_name,
          author_username: author.username,
          thread_id: thread.id,
          thread_type: thread.type,
        )
      end

      private

      sig { returns(::Discussion) }
      attr_reader :discussion
      sig { returns(Author) }
      attr_reader :author
    end
  end
end
