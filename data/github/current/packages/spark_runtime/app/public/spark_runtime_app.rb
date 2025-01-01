# typed: strict
# frozen_string_literal: true

module SparkRuntimeApp
  require "securerandom"
  require "digest"

  sig do
    params(
      current_user: User,
      name: T.nilable(String),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.create_runtime_app(current_user, name = Spark::RuntimeApp.generate_random_name)
    username = current_user.display_login

    spark_owner = SparkRuntime::AppOwner.ensure_owner(current_user)

    # Let's determine if the user has any existing runtime apps. First-time users
    # will be using the v1.1 ACA API, which requires a user object to be created in their API.
    is_first_app = Spark::RuntimeApp.where(user_id: current_user.id).empty?
    if is_first_app
      # Track that this is a new API for the user, per https://github.com/github/spark/issues/121#issuecomment-2957219927
      # We will eventually migrate all users to this new API version, but we need to track who is/isn't using it.
      SparkRuntime::OwnerApiKV::set_new_api_version(spark_owner.permanent_name)

      # Go and create the user in ACA, so that we can use the new API
      user_client = SparkRuntime::AcaUserManagementClient.new(current_user, spark_owner, true)
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
