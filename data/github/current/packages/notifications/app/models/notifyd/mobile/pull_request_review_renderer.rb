# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class PullRequestReviewRenderer

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
        subtitle = Subtitle.new(repository: review.repository, number: pull_request.number)

        Notifyd::Proto::Layouts::Mobile::Basic.new(
          title: title,
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

      sig { returns(String) }
      def title
        # NOTE: (@franciscoj 07/11/2022) This uses `T.unsafe` because
        # approved/commented/changes_requested predicates are not typed. These
        # come from a state machine defined on the ::PullRequestReview model,
        # which doesn't have types (for now)
        action =
          if T.unsafe(review).approved?
            "approved your pull request"
          elsif T.unsafe(review).commented?
            "wrote a review comment on your pull request"
          elsif T.unsafe(review).changes_requested?
            "requested changes on your pull request"
          else
            ""
          end

        "@#{review.user} #{action}"
      end
    end
  end
end
