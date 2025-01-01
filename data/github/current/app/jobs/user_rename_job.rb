# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UserRenameJob < ApplicationJob
  queue_as :critical

  retry_on_recoverable_exceptions

  def perform(user, new_login, actor, serialized_request_context = nil, serialized_spamurai_form_signals = nil, rename_reason = nil, rename_notes = nil)
    return if user.nil?
    with_write do
      user.rename!(
        new_login,
        actor: actor,
        serialized_request_context: serialized_request_context,
        serialized_spamurai_form_signals: serialized_spamurai_form_signals,
        rename_reason: rename_reason,
        rename_notes: rename_notes,
      )
    end
  end
end
