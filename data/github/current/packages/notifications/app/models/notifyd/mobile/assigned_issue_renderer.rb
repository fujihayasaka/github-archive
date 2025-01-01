# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class AssignedIssueRenderer
      extend T::Sig

      sig { params(issue: ::Issue, author: Author, event: ::IssueEvent).void }
      def initialize(issue:, author:, event:)
        @issue = issue
        @author = author
        @event = event
      end

      sig { returns(Notifyd::Proto::Layouts::Mobile::Basic) }
      def render
        thread = IssueThread.new(issue: issue)
        title = "@#{author.username} assigned you"
        subtitle = Subtitle.new(repository: issue.repository, number: issue.number)

        Notifyd::Proto::Layouts::Mobile::Basic.new(
          title: title.to_s,
          subtitle: subtitle.to_s,
          body: issue.body,
          url: event.permalink,
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
      sig { returns(::IssueEvent) }
      attr_reader :event
    end
  end
end
