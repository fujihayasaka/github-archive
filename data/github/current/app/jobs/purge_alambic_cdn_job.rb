# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class PurgeAlambicCdnJob < ApplicationJob
  queue_as :cdn

  locked_by timeout: 5.minutes, key: ->(job) { Array(job.arguments[0]["keys"]).sort.join(",") }

  retry_on_dirty_exit
  retry_on Faraday::Error
  retry_on AssetUploadable::Cdn::Error

  # Public: Purges a given surrogate key.
  #
  # options - Hash
  #           :key       - String surrogate key to purge.
  #
  # Returns nothing.
  def perform(options = {})
    options = options.with_indifferent_access
    keys = Array(options["keys"])
    keys.sort!

    AssetUploadable::Cdn.purge(*keys)
  end
end
