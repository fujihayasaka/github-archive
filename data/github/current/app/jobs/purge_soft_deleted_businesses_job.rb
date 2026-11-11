# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PurgeSoftDeletedBusinessesJob < ApplicationJob
  queue_as :purge_soft_deleted_businesses
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  schedule interval: 30.minutes, condition: -> { !GitHub.single_business_environment? }

  def perform
    Business.purgeable.pluck(:id).each do |business_id|
      DestroyBusinessJob.perform_later(business_id)
      GitHub.dogstats.increment("businesses_purged.count")
    end
  end
end
