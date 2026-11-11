# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::TabCounts
  class Loader
    include GitHub::ResilienceMixin

    CHANGED_FILES_COUNT_FALLBACK = 0
    CHECKS_COUNT_FALLBACK = 0

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class TabCountsData < T::Struct
      const :check_suites_count, Integer
      const :files_changed_count, Integer
      const :conversation_count, Numeric
      const :files_changed_count_limit_exceeded, T::Boolean
    end

    sig { params(pull_request: PullRequest, limit_config: PullRequests::PageData::Files::PageLimitConfig).returns(TabCountsData) }
    def self.load(pull_request:, limit_config:)
      tab_counts = new(pull_request:, limit_config:)
      tab_counts.load
    end

    sig { params(pull_request: PullRequest, limit_config: PullRequests::PageData::Files::PageLimitConfig).void }
    def initialize(pull_request:, limit_config:)
      @pull_request = pull_request
      @limit_config = limit_config
    end

    sig { returns(TabCountsData) }
    def load
      TabCountsData.new(
        check_suites_count: checks_count,
        conversation_count: @pull_request.total_comments,
        files_changed_count: files_changed_count,
        files_changed_count_limit_exceeded: @limit_config.files_changed_count_limit_exceeded?,
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

      @limit_config.apply_files_changed_count_limit do
        changed_files_count
      end
    end
  end
end
