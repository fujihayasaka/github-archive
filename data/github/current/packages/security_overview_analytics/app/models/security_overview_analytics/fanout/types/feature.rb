# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Types
      class Feature < T::Enum
        enums do
          CodeScanningPullRequestAlert = new("code_scanning_pull_request_alert")
        end
      end
    end
  end
end
