# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview
  class DuplicationIdentifier
    include GitHub::Memoizer

    DUPLICATION_IDENTIFIERS = [DuplicationIdentifiers::CosineSimilarity]

    sig { params(response: T.untyped, pull_request: PullRequest).returns(T.untyped) }
    def self.call(response:, pull_request:)
      new(response:, pull_request:).process!
    end

    sig { params(response: T.untyped, pull_request: PullRequest).void }
    def initialize(response:, pull_request:)
      @response = response
      @pull_request = pull_request
      @metric_tags = {}
      @existing_comments = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = [] } }
      @response_comments = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = [] } }
      @metrics_logger = DuplicationIdentifiers::MetricsLogger.new
      @results = []
    end

    sig { void }
    def process!
      return unless existing_comments.any?

      metrics_logger.log do
        extract_existing_comment_data!
        extract_response_comment_data!
        @result = DUPLICATION_IDENTIFIERS.map do |identifier|
          identifier.process!(
            pull_request_id: pull_request.id,
            response_comments: @response_comments,
            existing_comments: @existing_comments,
          )
        end
        @results.concat(@result)
        @result
      end
    end

    sig { returns(T.untyped) }
    def results
      @results.flat_map do |result|
        result.duplicates.compact
      end
    end

    private

    sig { returns(T.untyped) }
    attr_reader :response

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(DuplicationIdentifiers::MetricsLogger) }
    attr_reader :metrics_logger

    sig { void }
    def extract_existing_comment_data!
      existing_comments.each do |comment|
        @existing_comments[comment.path][comment.blob_position.to_s] << {
          body: comment.body,
          comment_id: comment.id,
          pull_request_review_thread_id: comment.pull_request_review_thread_id,
        }
      end
    end

    sig { returns(ActiveRecord::Relation) }
    memoize def existing_comments
      PullRequestReviewComment.where(pull_request_review_id: pull_request.reviews.copilot.select(:id))
    end

    sig { void }
    def extract_response_comment_data!
      Array.wrap(response[:copilot_references]).each do |reference|
        next if reference[:type] != "github.generated-pull-request-comment"

        path = reference[:data][:path]
        line = reference[:data][:line].to_s
        body = reference[:data][:body]
        comment_identifier = reference[:data][:comment_identifier].to_s

        T.must(T.must(@response_comments[path])[line]) << { body:, comment_identifier: }
      end
    end
  end
end
