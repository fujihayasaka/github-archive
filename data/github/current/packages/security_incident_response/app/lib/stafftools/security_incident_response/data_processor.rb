# typed: true
# frozen_string_literal: true

module Stafftools
  module SecurityIncidentResponse
    class DataProcessor
      class DataProcessingError < StandardError; end

      def initialize
        @data = nil
      end

      def process(data, type = :csv)
        case type
        in :csv
          data
          .then { |d| validate_csv(d) }
          .then { |d| parse_csv(d) }
          .then { |d| process_csv(d) }
          .then { |result| SecurityIncidentResponse::Csv.new(result) }
        else
          raise ArgumentError, "Invalid data type: #{type}"
        end
      end

      private

      def validate_csv(csv)
        raise DataProcessingError, "No CSV specified!" if csv.blank?

        required_values = ["org_id"]

        T.must(::CSV.foreach(csv.path, headers: true)).with_index(2) do |csv_row, row_number|
          row = T.cast(csv_row, ::CSV::Row)

          # check if required values are present
          required_values.each do |value|
            raise DataProcessingError, "CSV malformed, at least one row is missing required values for #{value}" if row[value].nil?
          end

          row.headers.each_with_index do |_header, index|
            value = row.fields[index]
            raise DataProcessingError, "CSV malformed, it appears that row #{row_number} is missing data" if value.nil?
          end
        end

        csv
      end

      def parse_csv(csv, options = {})
        output = []

        T.must(::CSV.foreach(csv.path, headers: true)).with_index(2) do |csv_row, _row_number|
          row = T.cast(csv_row, ::CSV::Row)

          data = row.headers.map.with_index { |header, index| [header, row.fields[index]] }.to_h

          output.append(data)
        end

        output
      end

      def process_csv(data, options = {})
        output = []

        data.each do |row|
          org_id = row["org_id"].to_i
          # get admins of org
          organization = ::Organization.find_by(id: org_id)
          if organization.present?
            admin_ids = organization.admins.map(&:id)

            admin_ids.each do |admin_user_id|
              output.append({
                user_id: admin_user_id,
                data: row
              })
            end
          else
            raise DataProcessingError, "Organization id:#{org_id} not found"
          end
        end

        raise DataProcessingError, "Parsing of CSV failed, please double check the format." if output.empty?

        output
      end
    end
  end
end
