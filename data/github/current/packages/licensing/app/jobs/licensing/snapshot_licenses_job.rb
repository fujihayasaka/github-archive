# typed: true
# frozen_string_literal: true

module Licensing
  class SnapshotLicensesJob < ApplicationJob
    queue_as :licensing
    retry_on_dirty_exit

    discard_on ActiveJob::DeserializationError

    resolve_tenant_context do |business|
      business
    end

    def perform(business)
      return unless business.present?
      GlobalInstrumenter.instrument("business_licenses.snapshot", business: business)
    end
  end
end
