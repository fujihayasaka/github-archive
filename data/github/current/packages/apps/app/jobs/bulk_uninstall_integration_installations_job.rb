# typed: strict
# frozen_string_literal: true

class BulkUninstallIntegrationInstallationsJob < ApplicationJob
  queue_as :bulk_uninstall_integration_installations

  retry_on_dirty_exit

  BATCH_SIZE = T.let(100, Integer)
  TIME_LIMIT = T.let(4.minutes, ActiveSupport::Duration)

  sig { params(actor_id: Integer, integration_id: Integer, staff_actor: T::Boolean).void }
  def perform(actor_id, integration_id, staff_actor: false)
    integration = Integration.find(integration_id)
    actor = User.find(actor_id)

    return unless integration.feature_enabled?(:bulk_uninstall)

    GitHub::SafeTimer.timeout(TIME_LIMIT) do |timer|
      IntegrationInstallation.throttle do
        installations = integration.installations

        installations.find_each(batch_size: BATCH_SIZE) do |installation|
          # Just in case we need a killswitch
          return unless integration.feature_enabled?(:bulk_uninstall)
          return unless Integration.locked_for_bulk_uninstalls?(integration)

          with_write do
            begin
              installation.uninstall(actor:, staff_actor:)
            rescue ActiveRecord::RecordNotFound
              GitHub.logger.info(
                "Installation not found while bulk uninstalling integration ID: #{integration.id}",
                "gh.job.name" => self.class.name,
                "gh.integration.id" => integration.id,
                "gh.integration.slug" => integration.slug,
                "gh.installation.id" => installation.id,
                "gh.actor.id" => actor.id,
                "gh.staff_actor" => staff_actor,
              )
            end
          end

          # Enqueue another job to avoid queue system from killing
          # this job for running too long.
          unless timer.run?
            self.class.perform_later(
              actor_id,
              integration_id,
              staff_actor:
            )
            return
          end
        end

        if installations.none?
          with_write { Integration.release_bulk_uninstalls_lock(integration) }
          return
        end
      end
    end
  end
end
