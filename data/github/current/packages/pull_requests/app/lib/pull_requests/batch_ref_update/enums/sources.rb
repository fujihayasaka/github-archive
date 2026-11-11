# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    module Enums
      class Sources < T::Enum
        enums do
          MaintainTrackingRef = new("maintain_tracking_ref")
        end
      end
    end
  end
end
