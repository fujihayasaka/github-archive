# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaKvClient < AcaBaseClient
    sig { returns(Spark::RuntimeApp) }
    attr_reader :runtime_app

    sig { returns(T.nilable(String)) }
    attr_reader :region

    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
        region: T.nilable(String)
      ).void
    end
    def initialize(current_user, runtime_app, region = nil)
      @runtime_app = runtime_app
      @region = region

      # Determine if we'll need to be using the new API, which is dependent on the owner of the specific runtime app.
      # We'll also want to take into account the feature flag for the owner of the runtime app.
      should_use_new_api = OwnerApiKV.is_new_api_version?(runtime_app.runtime_app_owner.permanent_name)
      should_use_owner_permanent_name = FeatureFlag.vexi.enabled?(:spark_kv_owner_urls, current_user, default: false)
      should_allow_beta_env = FeatureFlag.vexi.enabled?(:spark_allow_beta_env, current_user, default: false)

      client_url = if should_use_owner_permanent_name && should_use_new_api
        SparkRuntime::AcaUrls.kv_url_11(
          runtime_app.runtime_app_owner.permanent_name,
          runtime_app.permanent_name,
          should_allow_beta_env ? runtime_app.in_beta_environment? : false,
        )
      else
        SparkRuntime::AcaUrls.kv_url(
          runtime_app.runtime_app_owner.deploy_login,
          runtime_app.permanent_name,
          runtime_app.runtime_app_owner.is_segregated?,
          should_allow_beta_env ? runtime_app.in_beta_environment? : false,
        )
      end

      token = if should_allow_beta_env && runtime_app.in_beta_environment?
        GitHub.copilot_workbench_aca_beta_database_token
      else
        GitHub.copilot_workbench_aca_database_token
      end

      super(
        current_user,
        client_url,
        token,
        "kv"
      )
    end

    sig do
      params(
        meth: Symbol,
        endpoint: T.nilable(String),
        elapsed: T.any(Float, Numeric),
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def attributes_for_telemetry(meth, endpoint, elapsed)
      super.merge(extra_attributes_for_runtime_app(@runtime_app))
    end

    sig do
      params(
        collection_name: T.nilable(String),
      ).returns(AcaResponse)
    end
    def list(collection_name)
      endpoint = "list"
      rescue_from_aca_errors(:post, endpoint) do
        connection = create_connection
        connection.post(endpoint) do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.headers["x-ms-region"] = @region if @region
          aca_request.body = {
            AreAllUsersAndGlobalKeysReturned: true,
            EndUserName: nil,
            collectionName: collection_name
          }.to_json
        end
      end
    end

    sig do
      params(
        collection_name: T.nilable(String),
      ).returns(AcaResponse)
    end
    def list_collection(collection_name)
      rescue_from_aca_errors(:post, "list_collection") do
        connection = create_connection
        connection.post("list") do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.headers["x-ms-region"] = @region if @region
          aca_request.body = {
            AreAllUsersAndGlobalKeysReturned: true,
            EndUserName: nil,
            collectionName: collection_name
          }.to_json
        end
      end
    end

    sig do
      params(
        key: String,
        collection_name: T.nilable(String),
      ).returns(AcaResponse)
    end
    def get(key, collection_name)
      endpoint = "get"
      rescue_from_aca_errors(:post, endpoint) do
        connection = create_connection
        connection.post(endpoint) do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.headers["x-ms-region"] = @region if @region
          aca_request.body = {
            key: key,
            isGlobal: true,
            collectionName: collection_name,
          }.to_json
        end
      end
    end

    sig do
      params(
        key: String,
        value: String,
        collection_name: T.nilable(String),
      ).returns(AcaResponse)
    end
    def create_or_update(key, value, collection_name)
      endpoint = "createOrUpdate"
      rescue_from_aca_errors(:post, endpoint) do
        connection = create_connection
        connection.post(endpoint) do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.headers["x-ms-region"] = @region if @region
          aca_request.body = {
            key: key,
            value: value,
            isGlobal: true,
            collectionName: collection_name,
          }.to_json
        end
      end
    end

    sig do
      params(
        key: String,
        collection_name: T.nilable(String),
      ).returns(AcaResponse)
    end
    def remove(key, collection_name)
      endpoint = "remove"
      rescue_from_aca_errors(:post, endpoint) do
        connection = create_connection
        connection.post(endpoint) do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.headers["x-ms-region"] = @region if @region
          aca_request.body = {
            key: key,
            isGlobal: true,
            collectionName: collection_name,
          }.to_json
        end
      end
    end
  end
end
