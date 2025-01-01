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
        pull_request_id: Integer,
        response_comments: T.untyped,
        existing_comments: T.untyped,
      ).returns(
        PullRequests::Copilot::CodeReview::DuplicationIdentifiers::Result,
      )
    end
    def self.process!(pull_request_id:, response_comments:, existing_comments:)
      new(pull_request_id:, response_comments:, existing_comments:).process!
    end

    sig { params(pull_request_id: Integer, response_comments: T.untyped, existing_comments: T.untyped).void }
    def initialize(pull_request_id:, response_comments:, existing_comments:)
      @pull_request_id = pull_request_id
      @response_comments = response_comments
      @existing_comments = existing_comments
    end

    sig { returns(PullRequests::Copilot::CodeReview::DuplicationIdentifiers::Result) }
    def process!
      if existing_comments.none? || response_comments.none?
        Result.new(identifier_slug: self.class.slug, pull_request_id:, duplicates: [])
      else
        Result.new(identifier_slug: self.class.slug, pull_request_id:, duplicates:)
      end
    end

    private

    sig { returns(Integer) }
    attr_reader :pull_request_id

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
        comment_identifier: response_comment[:comment_identifier].to_s,
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
