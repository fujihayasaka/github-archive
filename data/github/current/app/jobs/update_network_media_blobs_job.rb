# typed: true
# frozen_string_literal: true

class UpdateNetworkMediaBlobsJob < ApplicationJob
  queue_as :lfs
  locked_by timeout: 10.minutes, key: ->(job) {
    job.arguments[0].with_indifferent_access["network_id"].to_i
  }
  class Error < Exception; end

  ALLOWED_ACTIONS = [
    :archive, :unarchive
  ].freeze

  retry_on StandardError, attempts: 20
  retry_on_dirty_exit

  def perform(options)
    options    = options.with_indifferent_access
    action     = options["action"].try(:to_sym)
    network_id = options["network_id"].try(:to_i)

    raise Error, "Must provide non-nil \"network_id\" argument to UpdateNetworkMediaBlobs job." unless network_id
    raise Error, "Must provide non-nil \"action\" argument to UpdateNetworkMediaBlobs job." unless action
    raise Error, "Unable to perform '#{action}' across `Media::Blob`s" unless ALLOWED_ACTIONS.include?(action)

    Media::Blob.from("`media_blobs` IGNORE INDEX FOR ORDER BY (PRIMARY)")
      .where("repository_network_id = ?", network_id)
      .find_each(batch_size: 100) do |blob|
      Media::Blob.throttle_writes do
        case action
        when :archive
          blob.archive
        when :unarchive
          blob.unarchive
        end
      end
    end
  end
end
