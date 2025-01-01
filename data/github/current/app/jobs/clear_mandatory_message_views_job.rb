# typed: true
# frozen_string_literal: true

require "github/ds_extensions"

class ClearMandatoryMessageViewsJob < ApplicationJob
  queue_as :clear_mandatory_message_views

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  SLICE_SIZE = 1_000

  def perform
    return unless GitHub.enterprise?

    # rubocop:todo GitHub/DoNotUseGlobalKv
    if viewed_records = GitHub.kv.mget_prefix(MandatoryMessage::VIEWED_KEY_PREFIX).value { nil }
      # rubocop:enable GitHub/DoNotUseGlobalKv
      viewed_records.keys.each_slice(SLICE_SIZE) do |slice|
        with_write { GitHub.kv.mdel(slice) } # rubocop:todo GitHub/DoNotUseGlobalKv
      end
    end
  end
end
