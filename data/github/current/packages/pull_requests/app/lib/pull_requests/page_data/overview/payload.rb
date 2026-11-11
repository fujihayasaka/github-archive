# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview
  class Payload
    class OverviewPayload < T::Struct
      const :description, T.nilable(String)
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
      )
    end
  end
end
