# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::DuplicationIdentifiers
  class MetricsLogger
    METRIC_NAME = "ccr_duplication_identifier_runs"

    sig { void }
    def initialize
      @metric_name = METRIC_NAME
      @metric_tags = Set.new
    end

    sig { params(block: T.proc.returns(T::Array[Result])).returns(T::Array[Result]) }
    def log(&block)
      results = instrument_with_timing_metrics!(&block)

      results.each do |result|
        logging_values = result.duplicates.compact.each_with_object({}).with_index do |(duplicate, acc), duplicate_index|
          namespace = "gh.copilot.code_review.duplication_identifier.results.#{result.identifier_slug}.duplicates.#{duplicate_index}"
          retained_comment = duplicate[:duplicate_of]

          acc["#{namespace}.duplicate_of.comment_id"] = retained_comment[:comment_id]
          acc["#{namespace}.duplicate_of.pull_request_review_thread_id"] = retained_comment[:pull_request_review_thread_id]
          acc["#{namespace}.duplicate_of.position"] = retained_comment[:position]
          acc["#{namespace}.duplicate_of.truncated_body"] = retained_comment[:body].truncate(100)
          acc["#{namespace}.truncated_body"] = duplicate[:body].truncate(100)
          acc["#{namespace}.position"] = duplicate[:position]
          acc["#{namespace}.score"] = duplicate[:score]

          retained_comment_identifier = (
            retained_comment[:comment_identifier].presence ||
            retained_comment[:comment_id].presence ||
            "unknown"
          ).to_s
          duplicate_comment_identifier = (duplicate[:comment_identifier].presence || "unknown").to_s

          instrument_hydro_metrics!(
            retained_comment_identifier:,
            duplicate_comment_identifier:,
          )
        end

        GitHub.logger.info(
          "Duplication identification process complete",
          {
            "gh.copilot.code_review.duplication_identifier.results.#{result.identifier_slug}.duplication_found" => result.duplication_found?,
            "gh.pull_request.id" => result.pull_request_id,
          }.merge(logging_values),
        )
        metric_tags << "#{result.identifier_slug}:#{result.duplication_found?}"
      end

      metric_tags << "found:#{results.any?(&:duplication_found?)}"

      instrument_dogstats_metrics!
      results
    end

    private

    sig { returns(Set) }
    attr_reader :metric_tags

    sig { returns(String) }
    attr_reader :metric_name

    sig { params(block: T.proc.returns(T::Array[Result])).returns(T::Array[Result]) }
    def instrument_with_timing_metrics!(&block)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results = block.call
      GitHub.dogstats.distribution("#{metric_name}.dist.time", GitHub::Dogstats.duration(start))

      results
    end

    sig { void }
    def instrument_dogstats_metrics!
      GitHub.dogstats.increment(metric_name, tags: metric_tags.to_a)
    end

    sig { params(retained_comment_identifier: String, duplicate_comment_identifier: String).void }
    def instrument_hydro_metrics!(retained_comment_identifier:, duplicate_comment_identifier:)
      payload = {
        retained_comment_identifier:,
        duplicate_comment_identifier:,
      }

      GlobalInstrumenter.instrument("copilot.reviews.v0.DuplicateComment", payload)
    end
  end
end
