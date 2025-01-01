# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaKvManagementClient < AcaBaseClient
    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
      ).void
    end
    def initialize(current_user, runtime_app)
      @runtime_app = runtime_app

      owner = T.must(runtime_app.runtime_app_owner.owner)
      should_use_new_api = OwnerApiKV.is_new_api_version?(runtime_app.runtime_app_owner.permanent_name)

      client_url = if should_use_new_api
        SparkRuntime::AcaUrls.management_kv_url_11(
          runtime_app.runtime_app_owner.permanent_name,
          runtime_app.permanent_name,
        )
      else
        SparkRuntime::AcaUrls.management_kv_url(
          runtime_app.runtime_app_owner.deploy_login,
          runtime_app.permanent_name,
        )
      end

      super(
        current_user,
        client_url,
        GitHub.copilot_workbench_aca_management_token,
        "management_kv"
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
      returns(AcaResponse)
    end
    def put_database
      rescue_from_aca_errors(:put, "databases") do
        connection = create_connection
        connection.put do |aca_request|
          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = {}.to_json # ACA wants an empty body
        end
      end
    end
  end
end
