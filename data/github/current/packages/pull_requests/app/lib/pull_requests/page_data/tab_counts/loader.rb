# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::TabCounts
  class Loader
    extend T::Sig
    include GitHub::ResilienceMixin

    CHANGED_FILES_COUNT_FALLBACK = 0
    CHECKS_COUNT_FALLBACK = 0

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class TabCountsData < T::Struct
      const :check_suites_count, Integer
      const :files_changed_count, Integer
      const :conversation_count, Numeric
    end

    sig { params(pull_request: PullRequest).returns(TabCountsData) }
    def self.load(pull_request:)
      tab_counts = new(pull_request:)
      tab_counts.load
    end

    sig { params(pull_request: PullRequest).void }
    def initialize(pull_request:)
      @pull_request = pull_request
    end

    sig { returns(TabCountsData) }
    def load
      TabCountsData.new(
        check_suites_count: checks_count,
        conversation_count: @pull_request.total_comments,
        files_changed_count: files_changed_count,
      )
    end

    private


    sig { returns(Integer) }
    def checks_count
      with_database_error_fallback(fallback: CHECKS_COUNT_FALLBACK) do
        @pull_request.latest_check_runs_count
      end
    end

    sig { returns(Integer) }
    def files_changed_count
      summary_diff = @pull_request.historical_comparison.async_diff(summary: true).sync

      changed_files_count = CHANGED_FILES_COUNT_FALLBACK
      begin
        changed_files_count = summary_diff.changed_files
      rescue GitRPC::Error => error
        Failbot.report error
      end

      changed_files_count
    end
  end
end
