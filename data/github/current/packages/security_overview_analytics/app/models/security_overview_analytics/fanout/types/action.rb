# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Types
      class Action < T::Enum
        enums do
          Initialize = new("initialize")
          Reconcile = new("reconcile")
        end
      end
    end
  end
end
