# typed: true
# frozen_string_literal: true

class RepairVulnerabilitiesIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile("vulnerability", {
    fields: ["updated_at"],
    limit: 500,
    accept: :globally_available?,
    include: [:vulnerable_version_ranges, :cwes],
  })
end
