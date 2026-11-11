# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ImportExportState < Platform::Enums::Base
      description "The state of an import or export of GitHub data."

      feature_flag :gh_migrator_import_to_dotcom

      value "PENDING", "The import or export is queued and waiting to be processed", value: 0
      value "EXPORTING", "The export is being processed", value: 1
      value "EXPORTED", "The export has been completed", value: 2
      value "FAILED", "The import or export is has encountered an error", value: 3
      value "FAILED_IMPORT", "The import encountered an error", value: 10
      value "WAITING", "The import archive is ready to be uploaded", value: 40
      value "ARCHIVE_UPLOADED", "The import archive has been uploaded", value: 50
      value "PREPARING", "The archive is being unpacked", value: 60
      value "CONFLICTS", "The import has conflicts to resolve", value: 70
      value "MAPPING", "Mappings are being applied to the import in a background job", value: 75
      value "READY", "The import is ready to be imported", value: 80
      value "IMPORTING", "The import is being processed", value: 90
      value "IMPORTED", "The import has completed", value: 100
      value "UNLOCKED", "The migration repositories have been unlocked", value: 110
    end
  end
end
