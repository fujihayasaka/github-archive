# typed: true
# frozen_string_literal: true

module Licensing
  class ProcessBusinessLicenseConsumptionExportJob < ApplicationJob
    # Using the critical queue because users are waiting for results
    queue_as :critical

    retry_on_recoverable_exceptions
    retry_on_dirty_exit

    def perform(export_id)
      export = Business::LicenseConsumptionExport.find_by(id: export_id)
      return unless export
      status = JobStatus.find(export.token)
      return unless status

      status.track do
        with_write { export.process }
      end
    end
  end
end
