# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::TabCounts
  class Payload
    class TabCountsPayload < T::Struct
      const :checksCount, Integer
      const :conversationCount, Numeric
      const :filesChangedCount, Integer
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
      ).call
    end

    sig do
      params(
        checks_count: Integer,
        conversation_count: Numeric,
        files_changed_count: Integer,
      ).void
    end
    def initialize(
      checks_count:,
      conversation_count:,
      files_changed_count:
    )
      @checks_count = checks_count
      @conversation_count = conversation_count
      @files_changed_count = files_changed_count

    end

    sig { returns(TabCountsPayload) }
    def call
      TabCountsPayload.new(
        checksCount: @checks_count,
        conversationCount:  @conversation_count,
        filesChangedCount: @files_changed_count
      )
    end
  end
end
