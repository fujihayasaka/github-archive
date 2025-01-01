# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UserRenameJob < ApplicationJob
  queue_as :critical

  retry_on_recoverable_exceptions

  def self.allow_async_enqueues?
    false
  end

  def perform(user, new_login, actor, serialized_request_context = nil, serialized_spamurai_form_signals = nil, rename_reason = nil, rename_notes = nil)
    return if user.nil?

    GitHub.logger.with_named_tags("gh.user.login" => user.login) do # rubocop:disable GitHub/DoNotAllowLogin - used in logging
      GitHub.logger.info("UserRenameJob enqueued",
        new_login: new_login,
      )
    end

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

    GitHub.logger.info("UserRenameJob successfully renamed user",
      "new_login" => new_login,
      "gh.user.login" => user.login, # rubocop:disable GitHub/DoNotAllowLogin - used in logging
    )

  rescue => e # rubocop:todo Lint/RescueException
    GitHub.logger.error("UserRenameJob error renaming user",
      :exception => e,
      "gh.user.login" => user.login, # rubocop:disable GitHub/DoNotAllowLogin - used in logging
      "new_login" => new_login,
    )

    raise e
  end
end
