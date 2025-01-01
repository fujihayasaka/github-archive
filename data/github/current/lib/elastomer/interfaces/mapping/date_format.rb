# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      # Static options for how a date string should be ingested by Elasticsearch.
      #
      # These options are used as the value of the `format` property of the `Date` mapping type. They represent only
      # those formats that we currently use; we expect this list to grow as we use new formats.
      #
      # For more details, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-date-format.html
      class DateFormat < T::Enum
        enums do
          StrictDateOptionalTime = new("strict_date_optional_time")
        end
      end
    end
  end
end
