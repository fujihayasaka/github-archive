# typed: true
# frozen_string_literal: true

class AttachMatchingAssetsJob < ApplicationJob
  use_primaries ApplicationRecord::Mysql1

  queue_as :attach_matching_assets

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 15.minutes, key: ->(job) {
    # Only let one job per issue process at the same time due
    # to the attaching not being thread safe.
    job.arguments[0]
  }

  discard_on ActiveJob::DeserializationError

  def perform(attacher, raw_data: nil, attaching_user: nil, detach_removed_assets: true)
    Attachment.attach(attacher, body_asset_matches(attacher, raw_data), attaching_user: attaching_user, detach_removed_assets: detach_removed_assets)
  end

  def body_asset_matches(attacher, raw_data)
    return AssetScanner.scan_raw_markdown(raw_data) unless raw_data.nil?
    attacher.body_asset_matches
  end
end
