# typed: true
# frozen_string_literal: true

class RefreshSponsorsPatreonTokensJob < ApplicationJob
  queue_as :patreon

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on(SponsorsPatreonClient::Error, wait: :polynomially_longer, attempts: 5)

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  sig { params(sponsors_patreon_user: SponsorsPatreonUser).void }
  def perform(sponsors_patreon_user)
    return unless GitHub.sponsors_enabled?

    ActiveRecord::Base.connected_to(role: :writing) do
      sponsors_patreon_user.refresh_tokens_or_destroy
    end
  end
end
