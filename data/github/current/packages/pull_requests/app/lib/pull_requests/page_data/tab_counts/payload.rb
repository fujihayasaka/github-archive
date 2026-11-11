# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::TabCounts
  class Payload
    class TabCountsPayload < T::Struct
      const :annotationsCount, Integer
      const :checksCount, Integer
      const :conversationCount, Numeric
      const :filesChangedCount, Integer
      const :filesChangedCountLimitExceeded, T::Boolean
      const :unresolvedConversationCount, Integer
      const :findingsCount, Integer
    end

    sig do
      params(
        tab_counts_data: PullRequests::PageData::TabCounts::Loader::TabCountsData
      ).returns(TabCountsPayload)
    end
    def self.call(tab_counts_data)
      new(
        annotations_count: tab_counts_data.annotations_count,
        checks_count: tab_counts_data.check_suites_count,
        conversation_count: tab_counts_data.conversation_count,
        files_changed_count: tab_counts_data.files_changed_count,
        files_changed_count_limit_exceeded: tab_counts_data.files_changed_count_limit_exceeded,
        unresolved_conversation_count: tab_counts_data.unresolved_conversation_count,
        findings_count: tab_counts_data.findings_count,
      ).call
    end

    sig do
      params(
        annotations_count: Integer,
        checks_count: Integer,
        conversation_count: Numeric,
        files_changed_count: Integer,
        files_changed_count_limit_exceeded: T::Boolean,
        unresolved_conversation_count: Integer,
        findings_count: Integer,
      ).void
    end
    def initialize(
      annotations_count:,
      checks_count:,
      conversation_count:,
      files_changed_count:,
      files_changed_count_limit_exceeded:,
      unresolved_conversation_count:,
      findings_count:
    )
      @annotations_count = annotations_count
      @checks_count = checks_count
      @conversation_count = conversation_count
      @files_changed_count = files_changed_count
      @files_changed_count_limit_exceeded = files_changed_count_limit_exceeded
      @unresolved_conversation_count = unresolved_conversation_count
      @findings_count = findings_count
    end

    sig { returns(TabCountsPayload) }
    def call
      TabCountsPayload.new(
        annotationsCount: @annotations_count,
        checksCount: @checks_count,
        conversationCount:  @conversation_count,
        filesChangedCount: @files_changed_count,
        filesChangedCountLimitExceeded: @files_changed_count_limit_exceeded,
        unresolvedConversationCount: @unresolved_conversation_count,
        findingsCount: @findings_count,
      )
    end
  end
end
