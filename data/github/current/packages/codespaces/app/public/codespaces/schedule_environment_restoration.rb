# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class ScheduleEnvironmentRestoration

    attr_reader :codespace

    class UnrestorableEnvironmentError < Error; end

    def self.call(codespace)
      new(codespace).call
    end

    def initialize(codespace)
      @codespace = codespace
    end

    def call
      refreshed = refresh_codespace

      raise UnrestorableEnvironmentError, "Environment #{codespace.guid} is not in a restorable state." unless refreshed && refreshed.restorable?
      CodespacesRestoreJob.perform_later(codespace: codespace)
    end

    private

    def refresh_codespace
      begin
        client.fetch_environment!(codespace.guid, include_deleted: true)

        # Reload to make sure we pick up the latest cached environment data, written by the fetch_environment! call
        # above.
        codespace.reload
      rescue ::Codespaces::VscsClient::BadResponseError
        nil
      end
    end

    def client
      ::Codespaces::VscsClient.for_codespace(codespace)
    end
  end
end
