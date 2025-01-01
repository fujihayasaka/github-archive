# typed: strict
# frozen_string_literal: true

module Codespaces
  class FlushSettingsSync < Command

    class InvalidEnv < Error; end

    sig { params(user: User, error_reporter: ErrorReporter).void }
    def initialize(
      user:,
      error_reporter: Codespaces::ErrorReporter.new
    )
      @user = user
      @error_reporter = error_reporter
    end

    sig { override.void }
    def perform
      # no need to flush if the user does not have any codespace
      return unless @user.codespaces.present?

      # no need to mint a codespace-scope token since settings sync only needs userId
      integration = Apps::Privileged.integration(:codespaces_production)
      access = integration.grant(@user)
      token, _ = access.redeem
      client.flush_user_cache(token)
    rescue Codespaces::SettingsSyncClient::SettingSyncFlushError => e
      @error_reporter.push(error: e.message)
    end

    private

    sig { returns(Codespaces::SettingsSyncClient) }
    def client
      @client ||= T.let(Codespaces::SettingsSyncClient.new, T.nilable(Codespaces::SettingsSyncClient))
    end
  end
end
