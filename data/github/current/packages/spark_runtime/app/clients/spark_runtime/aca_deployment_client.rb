# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaDeploymentClient < AcaBaseClient
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

      should_allow_beta_env = FeatureFlag.vexi.enabled?(:spark_allow_beta_env, current_user, default: false)

      should_use_new_api = OwnerApiKV.is_new_api_version?(runtime_app.runtime_app_owner.permanent_name)
      client_url = if should_use_new_api
        SparkRuntime::AcaUrls.management_app_deploys_url_11(
          runtime_app.runtime_app_owner.permanent_name,
          runtime_app.permanent_name,
          revision_name || "main",
          should_allow_beta_env ? runtime_app.in_beta_environment? : false,
        )
      else
        SparkRuntime::AcaUrls.management_app_deploys_url(
          runtime_app.runtime_app_owner.deploy_login,
          runtime_app.permanent_name,
          revision_name || "main",
          should_allow_beta_env ? runtime_app.in_beta_environment? : false,
        )
      end


      token = if should_allow_beta_env && runtime_app.in_beta_environment?
        GitHub.copilot_workbench_aca_beta_management_token
      else
        GitHub.copilot_workbench_aca_management_token
      end

      super(
        current_user,
        client_url,
        token,
        "deployment"
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
      params(
        data: T.untyped
      ).returns(AcaResponse)
    end
    def upload(data)
      rescue_from_aca_errors(:post, "upload") do
        connection = create_connection
        connection.request :multipart
        connection.post do |aca_request|
          aca_request.body = {
            file: Faraday::UploadIO.new(StringIO.new(data), "application/octet-stream", "bundle.zip"),
          }
        end
      end
    end
  end
end
