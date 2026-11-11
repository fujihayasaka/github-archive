# typed: strict
# frozen_string_literal: true

module Repositories
  class ReposdStoresTwirpClient
    class NotFoundError < StandardError; end

    SERVICE_PATH = "/twirp/reposd.stores.v1.Stores"

    sig { void }
    def initialize
      url = GitHub.reposd_twirp_url
      raise "GitHub.reposd_twirp_url is not configured." unless url

      @connection = T.let(
        GitHub::FaradayClient.internal("reposd-stores-twirp", url) do |f|
          f.options.timeout = 10
          f.options.open_timeout = 1
          f.request :json
          f.response :json
        end,
        Faraday::Connection
      )
    end

    # Gets a store by ID.
    #
    # @param id [String] The ID of the store to get.
    # @return [Hash, nil] The response hash, or nil if not found.
    sig { params(id: String).returns(T.nilable(T::Hash[String, T.untyped])) }
    def get_store(id:)
      return nil if id.empty?

      response = @connection.post("#{SERVICE_PATH}/GetStore") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = { id: id }.to_json
      end

      return nil if response.status == 404 || response.status == 400

      unless response.success?
        resp_body = response.body
        msg = resp_body.is_a?(Hash) ? resp_body["msg"] || resp_body["message"] : resp_body.to_s
        raise NotFoundError, "Failed to get store via reposd twirp: #{response.status} - #{msg}"
      end

      response.body
    end
  end
end
