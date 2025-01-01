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

    if viewed_records = EnterpriseAccounts::KV.store.mget_prefix(MandatoryMessage::VIEWED_KEY_PREFIX).value { nil }
      viewed_records.keys.each_slice(SLICE_SIZE) do |slice|
        with_write { EnterpriseAccounts::KV.store.mdel(slice) }
      end
    end
  end
end
