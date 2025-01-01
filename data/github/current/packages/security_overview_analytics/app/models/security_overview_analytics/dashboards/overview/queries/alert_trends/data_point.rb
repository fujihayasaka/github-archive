# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::DataPoint < T::Struct
          extend T::Sig

          DataPointHashShape = T.type_alias { { x: ::Date, y: Integer } }

          const :x, ::Date
          prop :y, Integer

          sig { returns(DataPointHashShape) }
          def to_h
            { x:, y: }
          end

          sig { params(other: AlertTrends::DataPoint).returns(T::Boolean) }
          def ==(other)
            to_h == other.to_h
          end
        end
      end
    end
  end
end
