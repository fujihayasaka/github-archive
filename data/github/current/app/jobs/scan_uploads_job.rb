# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job supports user asset scanning, as part of the Schaefer project.
# At the request of a Stafftools admin, this job fetches all uploads
# ever made by a user, and queues them up to be scanned by PhotoDNA.
class ScanUploadsJob < ApplicationJob
  retry_on_dirty_exit
  queue_as :scan_uploads

  SCAN_BATCH_SIZE = 1000

  def perform(target:)
    return if target.nil?

    if target.is_a?(Repositories::IRepository)
      Attachment.user_assets_for_entity(target).in_batches(of: SCAN_BATCH_SIZE) do |assets|
        process_batch(assets)
      end
    else
      target.assets.in_batches(of: SCAN_BATCH_SIZE) do |assets|
        process_batch(assets)
      end
    end
  end

  private

  def process_batch(assets)
    asset_ids = assets.pluck(:id)

    assets_except_known_hits = assets.subset_without_known_photo_dna_hits(asset_ids)

    assets_except_known_hits.each do |asset|
      GlobalInstrumenter.instrument "user_asset.scan_requested", user_asset: asset
    end
  end
end
