# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::DuplicationIdentifiers
  class Base
    extend T::Helpers

    abstract!

    sig { returns(String) }
    def self.slug
      T.must(self.name).demodulize.underscore
    end

    sig do
      params(
        response_comments: T.untyped,
        existing_comments: T.untyped,
      ).returns(
        PullRequests::Copilot::CodeReview::DuplicationIdentifiers::Result,
      )
    end
    def self.process!(response_comments:, existing_comments:)
      new(response_comments:, existing_comments:).process!
    end

    sig { params(response_comments: T.untyped, existing_comments: T.untyped).void }
    def initialize(response_comments:, existing_comments:)
      @response_comments = response_comments
      @existing_comments = existing_comments
    end

    sig { returns(PullRequests::Copilot::CodeReview::DuplicationIdentifiers::Result) }
    def process!
      if existing_comments.none? || response_comments.none?
        Result.new(identifier_slug: self.class.slug, duplicates: [])
      else
        Result.new(identifier_slug: self.class.slug, duplicates:)
      end
    end

    private

    sig { returns(T.untyped) }
    attr_reader :response_comments

    sig { returns(T.untyped) }
    attr_reader :existing_comments

    sig { abstract.returns(T.untyped) }
    def duplicates; end

    sig { params(response_comment: T.untyped, existing_comment: T.untyped, score: T.nilable(T.any(Integer, Float))).returns(T.untyped) }
    def build_duplicate_hash(response_comment:, existing_comment:, score:)
      {
        body: response_comment[:body].to_s,
        position: response_comment[:position].to_i,
        score:,
        duplicate_of: {
          body: existing_comment[:body].to_s,
          comment_id: existing_comment[:comment_id].to_i,
          pull_request_review_thread_id: existing_comment[:pull_request_review_thread_id].to_i,
          position: existing_comment[:position].to_i,
        },
      }
    end
  end
end
