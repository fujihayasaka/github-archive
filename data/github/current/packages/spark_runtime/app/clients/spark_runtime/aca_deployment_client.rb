
# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaDeploymentClient < AcaBaseClient
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
        T.let(SparkRuntime::AcaUrls.deployment_url(
          current_user.display_login,
          permanent_name,
          revision_name), String),
        GitHub.copilot_workbench_aca_deployment_token,
        "deployment"
      )
    end

    sig do
      params(
        data: T.untyped
      ).returns(AcaResponse)
    end
    def upload(data)
      rescue_from_aca_errors(:get) do
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
