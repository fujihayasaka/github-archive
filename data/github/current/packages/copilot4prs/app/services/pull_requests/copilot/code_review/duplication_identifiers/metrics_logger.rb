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

    sig { params(block: T.proc.returns(T::Array[Result])).void }
    def log(&block)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      results = yield

      GitHub.dogstats.distribution("#{@metric_name}.dist.time", GitHub::Dogstats.duration(start))

      results.each do |result|
        logging_values = result.duplicates.compact.each_with_object({}).with_index do |(duplicate, acc), duplicate_index|
          namespace = "gh.copilot.code_review.duplication_identifier.results.#{result.identifier_slug}.duplicates.#{duplicate_index}"

          acc["#{namespace}.duplicate_of.comment_id"] = duplicate[:duplicate_of][:comment_id]
          acc["#{namespace}.duplicate_of.pull_request_review_thread_id"] = duplicate[:duplicate_of][:pull_request_review_thread_id]
          acc["#{namespace}.duplicate_of.position"] = duplicate[:duplicate_of][:position]
          acc["#{namespace}.duplicate_of.truncated_body"] = duplicate[:duplicate_of][:body].truncate(100)
          acc["#{namespace}.truncated_body"] = duplicate[:body].truncate(100)
          acc["#{namespace}.position"] = duplicate[:position]
          acc["#{namespace}.score"] = duplicate[:score]
        end

        GitHub.logger.info(
          "Duplication identification process complete",
          {
            "gh.copilot.code_review.duplication_identifier.results.#{result.identifier_slug}.duplication_found" => result.duplication_found?,
            "gh.pull_request.id" => result.pull_request_id,
          }.merge(logging_values),
        )
        @metric_tags << "#{result.identifier_slug}:#{result.duplication_found?}"
      end

      @metric_tags << "found:#{results.any?(&:duplication_found?)}"
      GitHub.dogstats.increment(@metric_name, tags: @metric_tags.to_a)
    end
  end
end
