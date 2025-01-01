# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class SummaryStats < StatsBase
    extend T::Helpers
    include RequestorFilterable

    sig { params(organization_id: Integer, min_timestamp: Time, max_timestamp: Time).void }
    def initialize(organization_id, min_timestamp, max_timestamp)
      super organization_id, min_timestamp, max_timestamp
    end
  end
end
