# typed: true
# frozen_string_literal: true

##
## Tests for this are at: test/integration/api/runtime/deployment_test.rb
##

class Api::Runtime::Deployment < Api::Runtime::App
  include FeatureFlagHelper

  before do
    deliver_error!(404) unless current_user&.spark_enabled?
  end

  before do
    # This endpoint is only supported from Codespaces, not from deployed Sparks
    checker = Api::Runtime::IntegrationChecker.new(
      current_user,
      current_integration,
      [:codespaces_production])

    return if checker.allowed?

    # Anything else is invalid, so let's error out
    deliver_error! 401, message: "Integration auth is not supported for this endpoint"
  end

  get "/runtime/:app/deployment", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    runtime_app = find_runtime_app!

    control_access :runtime_write_deployment,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    revision_name = params[:revision_name]

    client = create_management_client!(runtime_app, revision_name)
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
  # The app may not exist if it wasn't created in the Spark Workbench. Another route is that
  # a user could use the GH CLI directly on a repository, which would mean that we didn't automatically
  # create the runtime app already.
  put "/runtime/:app/deployment", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    runtime_app = find_or_create_runtime_app!

    control_access :runtime_create_deployment,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Construct the client as early as possible because it does validation
    revision_name = params[:revision_name]
    client = create_management_client!(runtime_app, revision_name)

    # Read the request body and try to parse it as JSON
    data = request.body.read
    begin
      json_data = JSON.parse(data)
    rescue JSON::ParserError
      GitHub.logger.error("Invalid JSON in request body")
      deliver_error!(400, message: "Invalid JSON in request body")
    end

    # Extract the relevant fields from the JSON data
    environment_variables = json_data["environment_variables"]
    secrets = json_data["secrets"]
    visibility = json_data["visibility"]

    runtime_app.update!(visibility: visibility) if runtime_app && visibility.present?

    ### Create the app itself in ACA
    additional_params = {}

    workbench = Spark::Workbench.find_by(runtime_app: runtime_app)
    settings = SparkRuntime::AcaInterface.aca_settings(current_user, workbench) if workbench
    additional_params.merge!(settings) if settings

    # Fully public apps are not supported because we rely on GitHub accounts for access.
    #
    # The exceptions are:
    # * In development environments where we want to allow easier testing.
    # * Specific users on a FF who are aware they can only use static features (MSFT Store examples)
    #
    # Locally deployed apps cannot be properly authenticated into anyways (and therefore would never be usable) because
    # the production dotcom doesn't know about the locally created app. We therefore need to deploy them as public.
    is_dev_beta = Rails.env && Rails.env.development? && runtime_app.in_beta_environment?
    is_forced_public = current_user.feature_flag_enabled?(:copilot_workbench_force_public_deploy, default: false)
    is_private = !is_dev_beta && !is_forced_public

    aca_response = client.put_app({
      Username: current_user.display_login,
      EnvConfiguration: {
        EnvironmentVariables: environment_variables,
        Secrets: secrets
      },
      IsPrivate: is_private,
      IsSparkProxyEnabled: true, # We always want the proxy enabled for Workbench apps
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

    runtime_app = find_runtime_app!

    control_access :runtime_write_deployment,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    revision_name = params[:revision_name]

    client = create_management_client!(runtime_app, revision_name)
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

    runtime_app = find_runtime_app!

    control_access :runtime_write_deployment,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Read the URL parameters
    revision_name = params[:revision_name]
    revision = params[:revision]

    # Read the request body
    data = request.body.read

    # Send it to ACA
    client = SparkRuntime::AcaDeploymentClient.new(current_user, runtime_app, revision_name)
    aca_response = client.upload(data)

    if aca_response.status != 200
      GitHub.logger.error("Deployment upload failed", {
        "aca.status" => aca_response.status,
        "aca.value" => aca_response.value,
        "runtime.permanent_name" => runtime_app.permanent_name,
        "runtime.revision_name" => revision_name
      })
      deliver_error!(aca_response.status, message: "Failed to upload bundle")
    end

    runtime_app_deploy = Spark::RuntimeAppDeploy.create!(
      runtime_app:,
      revision: revision || "",
      display_name: revision_name || "",
    )

    should_scan = FeatureFlag.vexi.enabled?(:workbench_eyesite_scanning_uploads, current_user, default: false)
    if should_scan && runtime_app_deploy
      begin
        Workbench::ScanningBlobClient.upload(runtime_app.permanent_name, runtime_app_deploy.id.to_s, data)

        GlobalInstrumenter.instrument("runtime.deployment.scan_requested", {
          actor: current_user,
          deployment_id: runtime_app_deploy.id,
          upload_ip: request.ip,
          size: data.bytesize,
          uploaded_at: Time.now.utc.to_i,
        })

        rescue => e
          # Log the error but do not interrupt the main flow
          GitHub.logger.error("ScanningBlobClient upload failed: #{e.class} - #{e.message}", {
            "runtime.app_deploy_id" => runtime_app_deploy.id,
            "runtime.app_id" => runtime_app.id,
            "runtime.permanent_name" => runtime_app.permanent_name,
            "runtime.revision_name" => revision_name,
            "runtime.revision" => revision,
          })
      end
    end

    # The request was successful
    deliver_empty status: 200
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    deliver_error!(400, message: "Invalid app or revision")
  end

  def find_or_create_runtime_app!
    app_name = params[:app]
    runtime_app = Spark::RuntimeApp.find_by(permanent_name: app_name)

    if runtime_app.nil?
      begin
        # If the app doesn't exist yet, that means we didn't go through the Workbench flow to create it.
        # We don't want to allow creating apps in the beta environment unless they were done through the Workbench.
        # So we'll just always pass false for the beta environment here.
        SparkRuntimeApp.create_runtime_app(current_user, app_name, false)
        runtime_app = Spark::RuntimeApp.find_by(permanent_name: app_name)
      rescue ActiveRecord::RecordInvalid => e
        # Refuse on validation errors
        deliver_error!(400, message: e.message)
      end
    end

    runtime_app
  end

  def create_management_client!(runtime_app, revision_name)
    SparkRuntime::AcaAppManagementClient.new(current_user, runtime_app, revision_name)
  end
end
