# typed: true
# frozen_string_literal: true

class ScopedIntegrationInstallableExpirationExtensionJob < ApplicationJob
  queue_as :scoped_integration_installable_expiration_extension

  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: ->(job) do
    installable = job.arguments[0]
    "#{installable.ability_type}:#{installable.ability_id}"
  end

  def perform(installable, timestamp, entry_point:, token_last_eight: nil)
    installable.extend_expires_at!(timestamp, entry_point: entry_point, token_last_eight: token_last_eight)
  end
end
