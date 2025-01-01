# typed: true
# frozen_string_literal: true

##
## Tests for this are at: test/integration/api/runtime/deployment_test.rb
##

class Api::Runtime::Deployment < Api::App
  include FeatureFlagHelper

  before do
    deliver_error!(404) unless current_user.feature_enabled?(:copilot_workbench)
  end

  get "/runtime/:app/deployment", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :runtime_write_deployment,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    app = params[:app]
    revision_name = params[:revision_name]

    client = SparkRuntime::AcaManagementClient.new(current_user, app, revision_name)
    aca_response = client.get_app

    json_data = JSON.parse(aca_response.value)
    hostnames = json_data["hostnames"]

    if hostnames.nil? || hostnames.empty?
      deliver_error!(404, message: "App not found")
    end

    # TODO: Make this smarter and/or separate returning permanent vs custom/friendly names
    app_url = hostnames.last

    deliver_raw({ app_url: }, status: aca_response.status)
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid app or revision")
  end

  # Creating an app requires two steps: creating the app itself, and creating the database.
  put "/runtime/:app/deployment", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :runtime_write_deployment,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Read the URL parameters
    app = params[:app]
    revision_name = params[:revision_name]

    # Construct the client as early as possible because it does validation
    client = SparkRuntime::AcaManagementClient.new(current_user, app, revision_name)

    has_app = Spark::RuntimeApp.exists?(permanent_name: app)
    SparkRuntimeApp.create_runtime_app(current_user, app) unless has_app

    # Read the request body
    data = request.body.read
    json_data = JSON.parse(data)
    environment_variables = json_data["environment_variables"]
    secrets = json_data["secrets"]
    visibility = json_data["visibility"]

    ### Create the app itself in ACA
    additional_params = {}
    runtime_app = Spark::RuntimeApp.find_by(user_id: current_user.id, permanent_name: app)
    runtime_app.update!(visibility: visibility) if runtime_app && visibility.present?
    if runtime_app && runtime_app.friendly_name.present? && runtime_app.friendly_name != runtime_app.permanent_name
      additional_params[:CustomName] = runtime_app.friendly_name
    end

    aca_response = client.put_app({
        Username: current_user.display_login,
        EnvConfiguration: {
          EnvironmentVariables: environment_variables,
          Secrets: secrets
        },
        IsPrivate: true,
        IsSparkProxyEnabled: true,
        **additional_params,
      })

    if aca_response.status != 200
      halt deliver_raw(aca_response.value, status: aca_response.status)
    end

    json_data = JSON.parse(aca_response.value)
    hostnames = json_data["hostnames"]

    if hostnames.nil? || hostnames.empty?
      deliver_error!(404, message: "App not found")
    end

    app_url = hostnames.first

    deliver_raw({ app_url: }, status: aca_response.status)
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid app or revision")
  end

  delete "/runtime/:app/deployment", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :runtime_write_deployment,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    app = params[:app]
    revision_name = params[:revision_name]

    client = SparkRuntime::AcaManagementClient.new(current_user, app, revision_name)
    aca_response = client.delete_app

    if aca_response.status != 200
      deliver_error!(aca_response.status, message: "Failed to delete app")
    end

    # The request was successful
    deliver_empty status: 204
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid app or revision")
  end

  post "/runtime/:app/deployment/bundle", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :runtime_write_deployment,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Read the URL parameters
    app = params[:app]
    revision_name = params[:revision_name]

    # Read the request body
    data = request.body.read

    # Send it to ACA
    client = SparkRuntime::AcaDeploymentClient.new(current_user, app, revision_name)
    aca_response = client.upload(data)

    if aca_response.status != 200
      # Should we be recording failed deploys eventually?
      deliver_error!(aca_response.status, message: "Failed to upload bundle")
    end

    runtime_app = Spark::RuntimeApp.find_by(user_id: current_user.id, permanent_name: app)
    runtime_app_deploy = nil
    if runtime_app
      runtime_app_deploy = Spark::RuntimeAppDeploy.create!(
        runtime_app:,
        revision: "",  # TODO: Get this passed in
        display_name: revision_name || "",
      )
    end

    if current_user.feature_enabled?(:workbench_eyesite_scanning_uploads) && runtime_app_deploy
      begin
        blob_id = Workbench::ScanningBlobClient.upload(app, runtime_app_deploy.id, data)

        GlobalInstrumenter.instrument("runtime.deployment.scan_requested", {
          actor: current_user,
          deployment_id: runtime_app_deploy.id,
          upload_ip: request.ip,
          blob_id: blob_id,
          size: data.bytesize,
          uploaded_at: Time.now.utc.to_i,
        })

        rescue => e
          # Log the error but do not interrupt the main flow
          logger.error("ScanningBlobClient upload failed: #{e.class} - #{e.message}",
            "runtime.app_deploy_id": runtime_app_deploy.id,
            "runtime.app_id": runtime_app.id,
          )
      end
    end

    # The request was successful
    deliver_empty status: 200
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid app or revision")
  end
end
