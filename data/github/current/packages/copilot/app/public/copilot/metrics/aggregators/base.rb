# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Aggregators
      class Base
        include GitHub::Memoizer

        LOOKBACK_DAYS = 28

        sig { returns(::Organization) }
        attr_reader :owner
        sig { returns(Date) }
        attr_reader :start_date
        sig { returns(Date) }
        attr_reader :end_date

        sig { params(owner: ::Organization, start_date: Date).void }
        def initialize(owner:, start_date:)
          @owner = owner
          @start_date = start_date

          # For now, we only support weekly summaries that start on a Monday and end on a Sunday.
          raise ArgumentError, "start_date must be a Monday" unless start_date.monday?
          @end_date = T.let(start_date + 6.days, Date)
        end
      end
    end
  end
end
