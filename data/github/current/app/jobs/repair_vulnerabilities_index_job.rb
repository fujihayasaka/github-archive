# typed: true
# frozen_string_literal: true

class RepairVulnerabilitiesIndexJob < Elastomer::RepairJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :index_bulk

  reconcile("vulnerability", {
    fields: ["updated_at"],
    limit: 500,
    accept: :globally_available?,
    include: [:vulnerable_version_ranges, :cwes],
  })
end
