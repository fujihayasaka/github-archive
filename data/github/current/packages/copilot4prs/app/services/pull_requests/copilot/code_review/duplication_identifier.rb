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
      unless dedupe_pending_comments_enabled?
        return unless existing_comments.any?
      end

      metrics_logger.log do
        extract_existing_comment_data!
        extract_response_comment_data!

        deduplicate_pending_response_comments! if dedupe_pending_comments_enabled?

        process_with_identifiers(
          left_comments: @existing_comments,
          right_comments: @response_comments,
        ).tap do |result|
          @results.concat(result)
        end
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

    sig { params(left_comments: T.untyped, right_comments: T.untyped).returns(T::Array[DuplicationIdentifiers::Result]) }
    def process_with_identifiers(left_comments:, right_comments:)
      DUPLICATION_IDENTIFIERS.map do |identifier|
        identifier.process!(
          pull_request_id: pull_request.id,
          existing_comments: left_comments,
          response_comments: right_comments,
        )
      end
    end

    sig { returns(T::Boolean) }
    def dedupe_pending_comments_enabled?
      FeatureFlag.vexi.enabled?(:ccr_dedupe_new_comments, pull_request.repository, default: false)
    end

    sig { void }
    def deduplicate_pending_response_comments!
      results = metrics_logger.log do
        process_with_identifiers(
          left_comments: @response_comments.deep_dup,
          right_comments: @response_comments,
        )
      end

      results.each do |result|
        # get rid of any nils or self-duplicates
        result.duplicates.reject! { |c| c.nil? || c[:unique_id] == c[:duplicate_of][:unique_id] }

        # keep the first instance of a duplicate of unique_id, and discard the rest
        keepers = result.duplicates.each_with_object(Set.new) do |c, acc|
          acc << c[:unique_id] unless c[:duplicate_of][:unique_id].in?(acc)
        end

        # modify in place to keep only the unique duplicates
        result.duplicates.select! { |c| !keepers.include?(c[:unique_id]) }
      end

      # add the remaining results to the overall results
      @results.concat(results)
    end

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
        unique_id = SecureRandom.uuid

        T.must(T.must(@response_comments[path])[line]) << { body:, path:, comment_identifier:, unique_id: }
      end
    end
  end
end
