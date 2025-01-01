# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::TabCounts
  class Payload
    class TabCountsPayload < T::Struct
      const :checksCount, Integer
      const :conversationCount, Numeric
      const :filesChangedCount, Integer
      const :filesChangedCountLimitExceeded, T::Boolean
    end

    sig do
      params(
        tab_counts_data: PullRequests::PageData::TabCounts::Loader::TabCountsData
      ).returns(TabCountsPayload)
    end
    def self.call(tab_counts_data)
      new(
        checks_count: tab_counts_data.check_suites_count,
        conversation_count: tab_counts_data.conversation_count,
        files_changed_count: tab_counts_data.files_changed_count,
        files_changed_count_limit_exceeded: tab_counts_data.files_changed_count_limit_exceeded,
      ).call
    end

    sig do
      params(
        checks_count: Integer,
        conversation_count: Numeric,
        files_changed_count: Integer,
        files_changed_count_limit_exceeded: T::Boolean,
      ).void
    end
    def initialize(
      checks_count:,
      conversation_count:,
      files_changed_count:,
      files_changed_count_limit_exceeded:
    )
      @checks_count = checks_count
      @conversation_count = conversation_count
      @files_changed_count = files_changed_count
      @files_changed_count_limit_exceeded = files_changed_count_limit_exceeded
    end

    sig { returns(TabCountsPayload) }
    def call
      TabCountsPayload.new(
        checksCount: @checks_count,
        conversationCount:  @conversation_count,
        filesChangedCount: @files_changed_count,
        filesChangedCountLimitExceeded: @files_changed_count_limit_exceeded,
      )
    end
  end
end
