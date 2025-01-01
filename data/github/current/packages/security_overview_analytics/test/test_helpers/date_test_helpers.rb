# typed: true
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Test
    module TestHelpers
      module DateTestHelpers
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveSupport::TestCase }

        sig { params(from_date: ::Date, to_date: ::Date).void }
        def create_date_entries(from_date:, to_date:)
          columns = "id, date_value"
          values = (from_date..to_date).map do |date|
            "(#{::SecurityOverviewAnalytics::Date.id_from_date(date)}, #{::SecurityOverviewAnalytics::Date.connection.quote(date)})"
          end.join(", ")

          ::SecurityOverviewAnalytics::Date.connection.execute("INSERT IGNORE INTO soa_dates (#{columns}) VALUES #{values}")
        end
      end
    end
  end
end
