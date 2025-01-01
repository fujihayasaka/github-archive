# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaKvClient < AcaBaseClient
    sig do
      params(
        current_user: User,
        owner_login: String,
        database_name: String,
      ).void
    end
    def initialize(current_user, owner_login, database_name)
      super(
        current_user,
        database_name,
        nil,
        T.let(SparkRuntime::AcaUrls.kv_url(
          owner_login,
          database_name), String),
        GitHub.copilot_workbench_aca_database_token,
        "kv"
      )
    end

    sig do
      returns(AcaResponse)
    end
    def list
      endpoint = "list"
      rescue_from_aca_errors(:post, endpoint) do
        connection = create_connection
        connection.post(endpoint) do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = {
            AreAllUsersAndGlobalKeysReturned: true,
            EndUserName: nil
          }.to_json
        end
      end
    end

    sig do
      params(
        key: String,
      ).returns(AcaResponse)
    end
    def get(key)
      endpoint = "get"
      rescue_from_aca_errors(:post, endpoint) do
        connection = create_connection
        connection.post(endpoint) do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = {
            key: key,
            isGlobal: true,
          }.to_json
        end
      end
    end

    sig do
      params(
        key: String,
        value: String,
      ).returns(AcaResponse)
    end
    def create_or_update(key, value)
      endpoint = "createOrUpdate"
      rescue_from_aca_errors(:post, endpoint) do
        connection = create_connection
        connection.post(endpoint) do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = {
            key: key,
            value: value,
            isGlobal: true,
          }.to_json
        end
      end
    end

    sig do
      params(
        key: String,
      ).returns(AcaResponse)
    end
    def remove(key)
      endpoint = "remove"
      rescue_from_aca_errors(:post, endpoint) do
        connection = create_connection
        connection.post(endpoint) do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = {
            key: key,
            isGlobal: true,
          }.to_json
        end
      end
    end
  end
end
