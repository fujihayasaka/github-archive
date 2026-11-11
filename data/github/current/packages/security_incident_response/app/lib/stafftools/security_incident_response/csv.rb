# typed: true
# frozen_string_literal: true

module Stafftools
  module SecurityIncidentResponse
    class Csv
      def initialize(data)
        @row_data = data
      end

      def csv
        ::CSV.generate(force_quotes: true) do |csv|
          csv << ["user_id"] + @row_data.first[:data].keys.map(&:strip)
          @row_data.each do |row|
            csv << [row[:user_id]] + row[:data].keys.map do |key|
              row[:data][key]
            end
          end
        end
      end

      def to_s
        csv
      end
    end
  end
end
