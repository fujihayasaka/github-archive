# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class IssueRenderer

      sig { params(issue: ::Issue, author: Author).void }
      def initialize(issue:, author:)
        @issue = issue
        @author = author
      end

      sig { returns(Notifyd::Proto::Layouts::Mobile::Basic) }
      def render
        thread = IssueThread.new(issue: issue)
        title = TitleMention.new(author: author)
        subtitle = Subtitle.new(repository: issue.repository, number: issue.number)

        Notifyd::Proto::Layouts::Mobile::Basic.new(
          title: title.to_s,
          subtitle: subtitle.to_s,
          body: issue.body,
          url: issue.permalink,
          avatar_url: author.avatar_url,
          author_profile_name: author.profile_name,
          author_username: author.username,
          thread_id: thread.id,
          thread_type: thread.type,
        )
      end

      private

      sig { returns(::Issue) }
      attr_reader :issue
      sig { returns(Author) }
      attr_reader :author
    end
  end
end
