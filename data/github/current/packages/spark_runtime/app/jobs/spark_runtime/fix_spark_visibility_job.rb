# typed: strict
# frozen_string_literal: true

# This job is configured in config/background_job_queues/copilot-workbench.yml

module SparkRuntime
  class FixSparkVisibilityJob < ApplicationJob
    queue_as :spark_runtime_fix_visibility

    # https://thehub.github.com/epd/engineering/products-and-services/dotcom/background-jobs/best-practices/#retry_on_dirty_exit
    retry_on_dirty_exit
    # https://thehub.github.com/epd/engineering/products-and-services/dotcom/background-jobs/best-practices/#retry_on_recoverable_exceptions
    retry_on_recoverable_exceptions

    sig do
      params(
        user_id: Integer,
        organization_id: Integer,
      ).void
    end
    def perform(user_id, organization_id)
      return unless user = User.find_by(id: user_id)
      return unless organization = Organization.find_by(id: organization_id)

      # Find all Spark Runtime Apps which are visible to that organization and invalidate their tokens, to ensure
      # that the removed user no longer has access.
      # Unfortunately and currently, all tokens for all users on all affected
      # apps need to be purged, not just those belonging to the removed user.
      org_apps_count = 0

      Spark::RuntimeApp.where(visibility_organization_id: organization.id).find_each do |app|
        client = SparkRuntime::AcaAppManagementClient.new(user, app)
        client.purge_auth_for_app
        org_apps_count += 1
      end

      # Find all Spark Runtime Apps that the user owns and which are visible to the organization from which they
      # have been removed. In this case, we want to set their visibility to "only_owner" and clear the
      # visibility_organization_id to ensure they are no longer accessible to that organization.
      user_apps_count = T.let(0, T.untyped)
      Spark::RuntimeApp.throttle do
        with_write do
          user_apps_count = Spark::RuntimeApp.where(
            user_id: user.id,
            visibility_organization_id: organization.id
          ).update_all(
            visibility: "only_owner",
            visibility_organization_id: nil
          )
        end
      end

      # Log it
      GitHub.dogstats.count("spark.runtime.fix_visibility.org_apps", org_apps_count)
      GitHub.dogstats.count("spark.runtime.fix_visibility.user_apps", user_apps_count)

      attrs = {
        "gh.actor.login": user.display_login,
        "runtime.fix_visibility.org_apps": org_apps_count,
        "runtime.fix_visibility.user_apps": user_apps_count,
        "runtime.fix_visibility.user": user.id,
        "runtime.fix_visibility.organization": organization.id,
      }
      GitHub.logger.info("Spark Runtime job to fix visibility", attrs)

      payload = Workbench::TelemetryInstrumenter::Payload.new(
        event_type: "spark.runtime.fix_visibility",
        context: attrs,
        request_id: "",
        session_id: "",
        spark_id: "",
        user_analytics_tracking_id: "",
        user_id: user.id,
        restricted: false
      )
      GlobalInstrumenter.instrument(Workbench::Events::GENERIC, payload)
    end
  end
end
