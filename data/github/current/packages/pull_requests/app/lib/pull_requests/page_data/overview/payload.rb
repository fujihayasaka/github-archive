# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview
  class Payload
    class FileSummaryPayload < T::Struct
      const :path, String
      const :additions, Integer
      const :deletions, Integer
    end

    class ChangeSummaryPayload < T::Struct
      const :name, T.nilable(String)
      const :fileSummaries, T::Array[FileSummaryPayload]
    end

    class SinceSelectorPayload < T::Struct
      const :timestamp, String
      const :source, String
      const :selected, T::Boolean
    end

    class CopilotReviewSummaryPayload < T::Struct
      const :reviewId, Integer
      const :state, String
      const :submittedAt, String
      const :body, String
      const :commentCount, Integer
      const :reviewerLogin, String
      const :reviewerAvatarUrl, String
      const :url, String
    end

    class OverviewPayload < T::Struct
      const :description, T.nilable(String)
      const :descriptionText, T.nilable(String)
      const :changeHighlights, T::Array[ChangeSummaryPayload]
      const :sinceSelectors, T::Array[SinceSelectorPayload]
      const :lastActivityTimestamp, String
      const :copilotReviewSummary, T.nilable(CopilotReviewSummaryPayload)
    end

    sig do
      params(
        overview_data: PullRequests::PageData::Overview::Loader::OverviewData,
      ).returns(OverviewPayload)
    end
    def self.call(overview_data)
      new(overview_data:).call
    end

    sig do
      params(
        overview_data: PullRequests::PageData::Overview::Loader::OverviewData,
      ).void
    end
    def initialize(overview_data:)
      @overview_data = overview_data
    end

    sig { returns(OverviewPayload) }
    def call
      OverviewPayload.new(
        description: @overview_data.description,
        descriptionText: @overview_data.description_text,
        changeHighlights: @overview_data.change_highlights.map do |change_summary|
          ChangeSummaryPayload.new(
            name: change_summary.name,
            fileSummaries: change_summary.file_summaries.map do |file_summary|
              FileSummaryPayload.new(
                path: file_summary.path,
                additions: file_summary.additions,
                deletions: file_summary.deletions,
              )
            end,
          )
        end,
        sinceSelectors: @overview_data.since_selectors.map do |selector|
          SinceSelectorPayload.new(
            timestamp: selector.timestamp.iso8601,
            source: selector.source.serialize,
            selected: selector.selected,
          )
        end,
        lastActivityTimestamp: @overview_data.last_activity_timestamp.iso8601,
        copilotReviewSummary: build_copilot_review_summary,
      )
    end

    private

    sig { returns(T.nilable(CopilotReviewSummaryPayload)) }
    def build_copilot_review_summary
      summary = @overview_data.copilot_review_summary
      return nil unless summary

      CopilotReviewSummaryPayload.new(
        reviewId: summary.review_id,
        state: summary.state,
        submittedAt: summary.submitted_at.iso8601,
        body: summary.body_html,
        commentCount: summary.comment_count,
        reviewerLogin: summary.reviewer_login,
        reviewerAvatarUrl: summary.reviewer_avatar_url,
        url: summary.url,
      )
    end
  end
end
