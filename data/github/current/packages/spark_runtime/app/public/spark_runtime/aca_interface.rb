# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaInterface
    sig do
      params(
        current_user: User,
        permanent_name: String,
        friendly_name: String
      ).void
    end
    def self.notify_friendly_name_change(current_user, permanent_name, friendly_name)
      runtime_app = Spark::RuntimeApp.find_by(user_id: current_user.id, permanent_name:)
      return unless runtime_app

      client = SparkRuntime::AcaAppManagementClient.new(current_user, runtime_app)
      client.patch_app({ CustomName: friendly_name })
    end

    sig do
      params(
        current_user: User,
        workbench: Spark::Workbench,
      ).void
    end
    def self.notify_settings_changes(current_user, workbench)
      runtime_app = workbench.runtime_app
      return unless runtime_app

      settings = aca_settings(current_user, workbench)
      return unless settings

      client = SparkRuntime::AcaAppManagementClient.new(current_user, runtime_app)
      client.patch_app(settings)
    end

    sig do
      params(
        current_user: User,
        workbench: Spark::Workbench,
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def self.aca_settings(current_user, workbench)
      runtime_app = workbench.runtime_app
      return unless runtime_app

      allow_unfurls = runtime_app.visibility == "github"

      settings = {
        UnfurlTitle: allow_unfurls ? workbench.name : "",
        UnfurlDescription: allow_unfurls ? workbench.description : "",
      }

      # If we haven't reset the friendly name, don't need to send to ACA.
      # This is probably an error since we expect to set the name early though.
      settings[:CustomName] = runtime_app.friendly_name if runtime_app.friendly_name.present? && runtime_app.friendly_name != runtime_app.permanent_name

      settings
    end

    sig do
      params(
        current_user: User,
        permanent_name: String,
      ).void
    end
    def self.purge_auth_for_app(current_user, permanent_name)
      runtime_app = Spark::RuntimeApp.find_by(user_id: current_user.id, permanent_name:)
      return unless runtime_app

      client = SparkRuntime::AcaAppManagementClient.new(current_user, runtime_app)
      client.purge_auth_for_app
    end
  end
end
