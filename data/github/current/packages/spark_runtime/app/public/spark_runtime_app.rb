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

    app_info = ActiveRecord::Base.connected_to(role: :writing) do
      app = ::Spark::RuntimeApp.create!(
        user_id: current_user.id,
        permanent_name: name,
        friendly_name: name,   # We have to have something unique to start
        username: username
      )

      { app_id: app.id, permanent_name: app.permanent_name }
    end

    SparkRuntime::AppOwner.ensure_owner(current_user)

    database_url = create_runtime_database(current_user, username, app_info[:permanent_name])

    app_info.merge({
      database_url: database_url,
    })
  end

  sig do
    params(
      current_user: User,
      username: String,
      database_id: String,
    ).returns(T.nilable(String))
  end
  def self.create_runtime_database(current_user, username, database_id)
    client = SparkRuntime::AcaManagementClient.new(current_user, database_id)
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
    GitHub.logger.error("Error creating database: #{e.message}")
    nil
  end
end
