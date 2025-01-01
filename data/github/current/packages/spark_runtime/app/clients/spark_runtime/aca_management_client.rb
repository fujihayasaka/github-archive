# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaManagementClient < AcaBaseClient
    sig do
      params(
        current_user: User,
        permanent_name: String,
        revision_name: T.nilable(String)
      ).void
    end
    def initialize(current_user, permanent_name, revision_name = nil)
      super(
        current_user,
        permanent_name,
        revision_name,
        T.let(SparkRuntime::AcaUrls.management_app_url(
          current_user.display_login,
          permanent_name,
          revision_name), String),
        GitHub.copilot_workbench_aca_management_token,
        "management"
      )

      # We also manage KV creation on a slightly different base URL
      @kv_url = T.let(SparkRuntime::AcaUrls.management_kv_url(
        current_user.display_login,
        permanent_name), String)
    end

    sig do
      returns(AcaResponse)
    end
    def get_app
      rescue_from_aca_errors(:get, "apps") do
        connection = create_connection
        connection.get
      end
    end

    sig do
      params(
        values: T::Hash[Symbol, T.untyped]
      ).returns(AcaResponse)
    end
    def put_app(values)
      rescue_from_aca_errors(:put, "apps") do
        connection = create_connection
        connection.put do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = values.to_json
        end
      end
    end

    sig do
      params(
        values: T::Hash[Symbol, T.untyped]
      ).returns(AcaResponse)
    end
    def patch_app(values)
      rescue_from_aca_errors(:patch, "apps") do
        connection = create_connection
        connection.patch do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = values.to_json
        end
      end
    end

    sig do
      returns(AcaResponse)
    end
    def delete_app
      rescue_from_aca_errors(:delete, "apps") do
        connection = create_connection
        connection.delete
      end
    end

    sig do
      returns(AcaResponse)
    end
    def put_database
      rescue_from_aca_errors(:put, "databases") do
        connection = create_connection(@kv_url)
        connection.put do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = {}.to_json # ACA wants an empty body
        end
      end
    end
  end
end
