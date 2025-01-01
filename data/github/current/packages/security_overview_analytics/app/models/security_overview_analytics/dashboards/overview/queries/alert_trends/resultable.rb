# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        module AlertTrends::Resultable
          extend T::Sig
          extend T::Helpers

          abstract!

          sig { abstract.returns(AlertTrends::Base::RunQueryOutputAlias) }
          def to_h; end

          sig { params(other: AlertTrends::DataPoint).returns(T::Boolean) }
          def ==(other)
            to_h == other.to_h
          end
        end
      end
    end
  end
end
