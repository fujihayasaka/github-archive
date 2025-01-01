# typed: false
# frozen_string_literal: true

class BatchInactivateDeploymentsJob < BatchedJob
  include ActiveJob::InitiallyEnqueuedAt

  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 5

  queue_as :actions

  def process_batch(batch, environment:, **options)
    GitHub.dogstats.count("deployment.status.create_inactive", batch.size)

    GitHub.logger.info("processing batch of #{batch.size} deployment statuses",
      catalog_service: "github/actions",
      "code.function": "BatchInactivateDeploymentsJob#process_batch",
      batch_first_id: "#{batch.first&.id}",
      batch_last_id: "#{batch.last&.id}",
    )

    ApplicationRecord::Collab.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
      batch.each do |status|
        status_hash = {
          state: "inactive",
          deployment_id: status.deployment_id,
          creator_id: status.creator_id,
          environment: environment,
        }

        # Maintain the log_url of the previously successful DeploymentStatus
        status_hash[:log_url] = status.log_url

        status = DeploymentStatus.new(status_hash)
        begin
          deployment = Deployment.find_by(id: status.deployment_id)

          if deployment.statuses.count >= DeploymentStatus.max_per_deployment
            with_write do
              deployment.statuses.reorder(created_at: :asc).first.destroy!
            end

            GitHub.logger.info("Deleted oldest status for deployment #{deployment.id}",
              catalog_service: "github/actions",
              "code.function": "BatchInactivateDeploymentsJob#process_batch",
            )
          end

          with_write do
            status.save!
          end

        rescue ActiveRecord::RecordInvalid
          GitHub.logger.warn("Failed to create deployment status",
            catalog_service: "github/actions",
            "code.function": "BatchInactivateDeploymentsJob#process_batch",
            error: "#{status.errors.full_messages.join(", ")}",
          )
        end
      end
    end
  end

  def next_batch(repository_id:, environment:, timestamp: Time.now.utc, offset_item_id: 0, **options)
    return unless GitHub.actions_enabled?

    statuses_to_inactivate = ActiveRecord::Base.connected_to(role: :reading) do
      args = {
        environment: environment,
        repository_id: repository_id,
        inactive: DeploymentStatus::INACTIVE,
        batch_size: Arel.sql(BATCH_SIZE.to_s),
        offset_item_id: offset_item_id,
      }
      status_ids = DeploymentStatus.connection.select_rows(Arel.sql(<<-SQL, **args)).flatten
        SELECT deployment_statuses.id
          FROM deployments
          JOIN deployment_statuses ON deployments.latest_deployment_status_id = deployment_statuses.id
        WHERE
          deployments.latest_status_state != :inactive
          AND deployments.latest_environment = :environment
          AND deployments.repository_id = :repository_id
          AND deployments.transient_environment = 0
          AND deployment_statuses.id > :offset_item_id
          ORDER BY deployment_statuses.id ASC
          LIMIT :batch_size;
      SQL

      DeploymentStatus.where(id: status_ids).to_a
    end
  end
end
