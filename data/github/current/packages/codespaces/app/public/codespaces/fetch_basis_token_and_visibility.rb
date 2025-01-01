# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class FetchBasisTokenAndVisibility < Command
    attr_reader :codespace, :port

    def initialize(codespace:, port:)
      @codespace = codespace
      @port = port
    end

    def perform
      fetch_tunnel_access_token_and_visibility
    rescue Codespaces::Client::BadResponseError => e
      record_error(e) unless e.status == 404
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      record_error(e)
    end

    def fetch_tunnel_access_token_and_visibility
      client.fetch_tunnel_access_token_and_visibility(codespace_id: codespace.guid, port: port)
    end

    def record_error(error)
      Failbot.report(
        error,
        "catalog_service" => "github/codespaces",
        "gh.codespaces.guid" => codespace.guid,
        "gh.codespaces.vscs_target" => codespace.vscs_target,
        "gh.codespaces.region" => codespace.location,
      )
    end

    def client
      @client ||= Codespaces::VscsClient.for_codespace(codespace)
    end
  end
end
