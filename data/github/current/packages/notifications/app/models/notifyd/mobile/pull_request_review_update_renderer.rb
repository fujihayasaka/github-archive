# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class PullRequestReviewUpdateRenderer
      extend T::Sig

      sig { params(review: ::PullRequestReview, pull_request: ::PullRequest).void }
      def initialize(review:, pull_request:)
        @review = review
        @pull_request = pull_request
      end

      sig { returns(Notifyd::Proto::Layouts::Mobile::Basic) }
      def render
        user = review.user
        author = user ? AuthorUser.new(user: user) : NullAuthor.new
        thread = PullRequestThread.new(pull_request: pull_request)
        title = TitleMention.new(author: author)
        subtitle = Subtitle.new(repository: review.repository, number: pull_request.number)

        Notifyd::Proto::Layouts::Mobile::Basic.new(
          title: title.to_s,
          subtitle: subtitle.to_s,
          body: review.body,
          url: review.permalink,
          avatar_url: author.avatar_url,
          author_profile_name: author.profile_name,
          author_username: author.username,
          thread_id: thread.id,
          thread_type: thread.type,
        )
      end

      private

      sig { returns(::PullRequestReview) }
      attr_reader :review
      sig { returns(::PullRequest) }
      attr_reader :pull_request
    end
  end
end
