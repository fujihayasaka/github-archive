# typed: strict
# frozen_string_literal: true

class DeleteSparkRuntimeAppJob < ApplicationJob
  queue_as :delete_spark_runtime_app
  retry_on_dirty_exit

  sig { params(user_id: Integer, app_name: String).void }
  def perform(user_id, app_name)
    # Make sure associated ACA app is shut down and removed.
    if user = User.find_by(id: user_id)
      return unless user.feature_flag_enabled?(:delete_spark_runtime_app, default: false)

      if app = Spark::RuntimeApp.find_by(user: user, permanent_name: app_name)
        client = SparkRuntime::AcaAppManagementClient.new(user, app)
        client.delete_app

        ActiveRecord::Base.connected_to(role: :writing) { app.destroy }
      end
    end
  end
end
