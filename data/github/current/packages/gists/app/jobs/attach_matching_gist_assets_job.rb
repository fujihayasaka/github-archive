# typed: true
# frozen_string_literal: true

class AttachMatchingGistAssetsJob < ApplicationJob
  use_primaries ApplicationRecord::Mysql1

  queue_as :attach_matching_assets

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 15.minutes, key: ->(job) {
    # Only let one job per gist process at the same time due
    # to the attaching not being thread safe.
    job.arguments[0]
  }

  discard_on ActiveJob::DeserializationError

  def perform(gist, contents)
    body_asset_matches = T.let([], T::Array[T.untyped])
    contents.each do |file|
      filename, data, delete = file[:name].to_s.strip, file[:value], !!file[:delete]
      if !delete && filename.end_with?(".md")
        matches = AssetScanner.scan_raw_markdown(data)
        body_asset_matches += matches
      end
    end

    # As all gist revisions are stored in git history, we must retain attachment associations,
    # even if an asset is removed in the most recent revision
    Attachment.attach(gist, body_asset_matches, detach_removed_assets: false)
  end
end
