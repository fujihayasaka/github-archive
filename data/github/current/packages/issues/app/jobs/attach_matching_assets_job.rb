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

  def perform(attacher)
    body_asset_matches = attacher.body_asset_matches
    Attachment.attach(attacher, body_asset_matches)
  end
end
