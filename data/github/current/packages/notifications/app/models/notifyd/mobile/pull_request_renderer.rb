# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class PullRequestRenderer

      sig { params(pull_request: ::PullRequest, author: Author).void }
      def initialize(pull_request:, author:)
        @pull_request = pull_request
        @author = author
      end

      sig { returns(Notifyd::Proto::Layouts::Mobile::Basic) }
      def render
        thread = PullRequestThread.new(pull_request: pull_request)
        title = TitleMention.new(author: author)
        subtitle = Subtitle.new(repository: pull_request.repository, number: pull_request.number)

        Notifyd::Proto::Layouts::Mobile::Basic.new(
          title: title.to_s,
          subtitle: subtitle.to_s,
          body: pull_request.body,
          url: pull_request.permalink,
          avatar_url: author.avatar_url,
          author_profile_name: author.profile_name,
          author_username: author.username,
          thread_id: thread.id,
          thread_type: thread.type,
        )
      end

      private

      sig { returns(::PullRequest) }
      attr_reader :pull_request
      sig { returns(Author) }
      attr_reader :author
    end
  end
end
