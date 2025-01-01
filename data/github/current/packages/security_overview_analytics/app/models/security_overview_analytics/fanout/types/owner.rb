# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Types
      class Owner < T::Enum
        enums do
          Organization = new("organization")
          User = new("user")
        end
      end
    end
  end
end
