# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Types
      class TenantScope < T::Enum
        enums do
          Business = new("business")
          Organization = new("organization")
          User = new("user")
        end
      end
    end
  end
end
