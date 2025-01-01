# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class IssueCommentRenderer
      extend T::Sig

      sig { params(issue_comment: ::IssueComment, issue: ::Issue, author: Author).void }
      def initialize(issue_comment:, issue:, author: NullAuthor.new)
        @issue_comment = issue_comment
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
          body: issue_comment.body,
          url: issue_comment.permalink,
          avatar_url: author.avatar_url,
          author_profile_name: author.profile_name,
          author_username: author.username,
          thread_id: thread.id,
          thread_type: thread.type,
        )
      end

      private

      sig { returns(::IssueComment) }
      attr_reader :issue_comment
      sig { returns(::Issue) }
      attr_reader :issue
      sig { returns(Author) }
      attr_reader :author
    end
  end
end
