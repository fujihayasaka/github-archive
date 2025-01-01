# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaAppManagementClient < AcaBaseClient
    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
        revision_name: T.nilable(String)
      ).void
    end
    def initialize(current_user, runtime_app, revision_name = nil)
      @runtime_app = runtime_app
      @revision_name = revision_name

      # Determine if we'll need to be using the new API, which is dependent on the owner of the specific runtime app.
      # We'll also want to take into account the feature flag for the owner of the runtime app.
      should_use_new_api = OwnerApiKV.is_new_api_version?(runtime_app.runtime_app_owner.permanent_name)

      client_url = if should_use_new_api
        SparkRuntime::AcaUrls.management_app_url_11(
          runtime_app.runtime_app_owner.permanent_name,
          runtime_app.permanent_name,
          revision_name
        )
      else
        SparkRuntime::AcaUrls.management_app_url(
          runtime_app.runtime_app_owner.deploy_login,
          runtime_app.permanent_name,
          revision_name
        )
      end

      super(
        current_user,
        client_url,
        GitHub.copilot_workbench_aca_management_token,
        "management_apps"
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
      super.merge(extra_attributes_for_runtime_app(@runtime_app, @revision_name))
    end

    sig do
      params(
        meth: Symbol,
        endpoint: T.nilable(String),
      ).returns(T::Array[String])
    end
    def tags_for_datadog(meth, endpoint)
      super.concat(extra_tags_for_app_revisions(@revision_name))
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
    def purge_auth_for_app
      rescue_from_aca_errors(:post, "purge_auth") do
        connection = create_connection
        connection.post("purgeAuth")
      end
    end
  end
end
