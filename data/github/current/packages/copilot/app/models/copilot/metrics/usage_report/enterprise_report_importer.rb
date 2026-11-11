# typed: true
# frozen_string_literal: true

module Copilot::Metrics
  # NOTE: Despite the name, this importer is used for both enterprise- and organization-level
  # usage reports. Renaming would be a breaking change, so keep this in sync with both uses.
  module UsageReport::EnterpriseReportImporter
    # Path where exported production files can be placed for local development / debugging
    IMPORT_DATA_PATH = ENV.fetch("COPILOT_METRICS_IMPORT_PATH", "")

    # Check if imported production data is available
    sig { returns(T::Boolean) }
    def self.imported_data_available?
      return false if IMPORT_DATA_PATH.empty?
      !imported_json_files.empty?
    end

    # Get the list of available JSON files for import
    sig { returns(T::Array[String]) }
    def self.imported_json_files
      return [] if IMPORT_DATA_PATH.empty?
      return [] unless Dir.exist?(IMPORT_DATA_PATH)
      Dir.glob(File.join(IMPORT_DATA_PATH, "*.json"))
    end

    # Get the filename of imported data if available
    sig { returns(T.nilable(String)) }
    def self.imported_data_filename
      return nil if IMPORT_DATA_PATH.empty?
      return nil unless imported_data_available?
      # Return just the basename of the file, not the full path
      first_file = imported_json_files.first
      return nil if first_file.nil?
      File.basename(first_file)
    end

    # Loads imported JSON data as a Kusto dataset for local development / debugging
    sig { params(json_file_path: Pathname, enterprise_id: T.nilable(Integer), organization_id: T.nilable(Integer), date: T.nilable(Date)).returns(Kusto::Data::Dataset) }
    def self.load_json_file_as_dataset(json_file_path, enterprise_id: nil, organization_id: nil, date: Date.yesterday)
      data = JSON.parse(File.read(json_file_path))

      # Extract the day_totals array and other fields from JSON
      day_totals = data["day_totals"]
      report_start_day = data["report_start_day"]
      report_end_day = data["report_end_day"]

      # Determine which ID to use (organization_id takes precedence)
      entity_id = organization_id || enterprise_id
      entity_id_key = organization_id ? "organization_id" : "enterprise_id"

      # Override entity ID in the data to match the requested entity_id
      # This allows using sample data files for any enterprise/organization in development
      day_totals.each do |record|
        record[entity_id_key] = entity_id.to_s
      end

      # If a specific date is requested, filter to that date only
      if date
        day_totals = day_totals.select { |record| record["day"] == date.to_s }
      end

      # Wrap the data in the format that generate_datatable_response expects
      # Use the requested entity_id, not the one from the JSON file
      rows = [[day_totals, entity_id.to_s, report_start_day, report_end_day]]

      UsageReport::EnterpriseDailyFactory.generate_datatable_response(
        enterprise_id: enterprise_id,
        organization_id: organization_id,
        date: date || Date.yesterday,
        rows: rows
      )
    end
  end
end
