# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PurgeFlaggedUploadsJob < ApplicationJob
  queue_as :purge_flagged_uploads

  schedule interval: 1.day, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform
    PhotoDnaHit.purgeable.in_batches(of: BATCH_SIZE) do |hit_batch|
      PhotoDnaHit.throttle do
        hit_batch.where.not(uploader_id: uploaders_to_exclude(hit_batch)).each do |hit|
          with_write { hit.purge_content! }
        end
      end
    end
  end

  private

  def uploaders_to_exclude(batch)
    uploader_ids = batch.pluck(:uploader_id)
    LegalHold.where(user_id: uploader_ids).pluck(:user_id)
  end
end
