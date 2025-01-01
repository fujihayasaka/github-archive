# typed: strict
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Codespaces
  # Public: Interface to the VS Code Settings Sync service
  class SettingsSyncClient < Client
    extend T::Sig

    class SettingSyncFlushError < Codespaces::Error; end

    INSIDERS_SETTINGS_SYNC_URL = "https://vscode-sync-insiders.trafficmanager.net/v1/"
    STABLE_SETTINGS_SYNC_URL = "https://vscode-sync.trafficmanager.net/v1/"
    TEST_SETTINGS_SYNC_URL = "https://vscode-sync-test.trafficmanager.net/v1/"

    sig { params(kwargs: T.untyped).void }
    def initialize(**kwargs)
      super **kwargs
    end

    sig { params(token: String).void }
    def flush_user_cache(token)
      settings_sync_api(:post, "auth/reset", token: token)
    end

    private

    sig { params(method: Symbol, path: String, token: String).void }
    def settings_sync_api(method, path, token:)
      headers = {
        "Content-Type" => "application/json",
        "X-Account-Type" => "github",
        "Authorization" => "Bearer #{token}",
      }
      insider_response = if method == :get
        settings_sync_insiders_connection.get(path, "", headers)
      else
        settings_sync_insiders_connection.run_request(method, path, "", headers)
      end

      stable_response = if method == :get
        settings_sync_stable_connection.get(path, "", headers)
      else
        settings_sync_stable_connection.run_request(method, path, "", headers)
      end

      if !stable_response.success?
        raise SettingSyncFlushError, "Fail to flush stable settings sync"
      elsif !insider_response.success?
        raise SettingSyncFlushError, "Fail to flush insiders settings sync"
      end
    rescue Faraday::TimeoutError
      raise TimeoutError, request_err_message("Timeout exceeded", method)
    rescue Faraday::ConnectionFailed => e
      raise ConnectionFailed, request_err_message("Connection failed: #{e.message}", method)
    end

    sig { returns(Faraday::Connection) }
    def settings_sync_insiders_connection
      @insiders_connection ||=
        T.let(connection_for(INSIDERS_SETTINGS_SYNC_URL), T.nilable(Faraday::Connection))
    end

    sig { returns(Faraday::Connection) }
    def settings_sync_stable_connection
      @stable_connection ||=
        T.let(connection_for(STABLE_SETTINGS_SYNC_URL), T.nilable(Faraday::Connection))
    end

    sig { returns(Faraday::Connection) }
    def settings_sync_test_connection
      @test_connection ||=
        T.let(connection_for(TEST_SETTINGS_SYNC_URL), T.nilable(Faraday::Connection))
    end
  end
end
