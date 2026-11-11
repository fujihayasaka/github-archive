# typed: strict
# frozen_string_literal: true

module SparkRuntimeApp
  require "securerandom"
  require "digest"

  sig do
    params(
      current_user: User,
      name: T.nilable(String),
      use_beta_env: T::Boolean,
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.create_runtime_app(current_user, name, use_beta_env)
    name ||= Spark::RuntimeApp.generate_random_name
    username = current_user.display_login
    spark_owner = SparkRuntime::AppOwner.ensure_owner(current_user)
    should_allow_beta_env = FeatureFlag.vexi.enabled?(:spark_allow_beta_env, current_user, default: false)

    raise SparkRuntime::SparkRuntimeError.new "Feature flag for beta environment is not enabled for this user" if !should_allow_beta_env && use_beta_env

    # Let's determine if the user has any existing runtime apps. First-time users
    # will be using the v1.1 ACA API, which requires a user object to be created in their API.
    # Any user who already has an app will assumed to be on 1.0 API if their API version is not set.
    is_first_app = !Spark::RuntimeApp.exists?(user_id: current_user.id)
    SparkRuntime::OwnerApiKV::set_new_api_version(spark_owner.permanent_name) if is_first_app

    # We'll also just always re-create the user if we're using the beta environment, since there are no downsides
    # to do doing so, this won't occur on enough scale to matter, and tracking it is more complex than it's worth.
    if use_beta_env || is_first_app
      use_new_api = SparkRuntime::OwnerApiKV::is_new_api_version?(spark_owner.permanent_name)
      user_client = SparkRuntime::AcaUserManagementClient.new(current_user, spark_owner, use_new_api, use_beta_env)
      response = user_client.put_user
      if !response.call_succeeded?
        # If we fail to create the user, we will raise an error. In development, we can
        # ignore this error because the developer may not have the appropriate ACA tokens in the environment
        # and the `monalisa` user should already be set-up anyways.
        is_development = Rails.env && Rails.env.development?
        raise SparkRuntime::SparkRuntimeError.new "Failed to create ACA user" unless is_development
      end
    end

    app = ActiveRecord::Base.connected_to(role: :writing) do
      Spark::RuntimeApp.create!(
        user_id: current_user.id,
        permanent_name: name,
        friendly_name: name,   # We need to have something unique to start
        username: username,
        owner_id: spark_owner.id,
      )
    end

    app.set_in_beta_environment(use_beta_env)

    database_url = create_runtime_database(current_user, username, app)

    {
      app_id: app.id,
      database_url: database_url,
      permanent_name: app.permanent_name
    }
  end

  sig { params(user: User, app_name: String).void }
  def self.delete_runtime_app(user, app_name)
    # Make sure that the ACA app is shut down and delete the app record. This runs in
    # a background job to prevent HTTP request timing from causing issues.
    DeleteSparkRuntimeAppJob.perform_later(user.id, app_name)
  end

  sig do
    params(
      current_user: User,
      username: String,
      runtime_app: Spark::RuntimeApp,
    ).returns(T.nilable(String))
  end
  def self.create_runtime_database(current_user, username, runtime_app)
    # For now, we have matching one-to-one names for app -> DB
    database_id = runtime_app.permanent_name

    client = SparkRuntime::AcaKvManagementClient.new(current_user, runtime_app)
    aca_response = client.put_database

    if aca_response.status != 200
      GitHub.logger.error("Spark KV database not created",
        "aca.http_status": aca_response.status,
        "aca.response_body": aca_response.value,
        "gh.actor.id": current_user.id,
        "gh.actor.login": current_user.display_login,
        "runtime.permanent_name": database_id)
      return nil
    end

    json_data = JSON.parse(aca_response.value)
    hostname = json_data["hostname"]

    if hostname.nil?
      GitHub.logger.error("Spark KV database created but no hostname returned",
        "gh.actor.id": current_user.id,
        "gh.actor.login": current_user.display_login,
        "runtime.permanent_name": database_id)
      return nil
    end

    hostname
  rescue => e
    # Don't let DB creation stop the Spark creation flow
    # TODO: We need to somehow eventually try to create the database again
    GitHub.logger.error("Error creating database: #{e.message}")
    nil
  end
end
