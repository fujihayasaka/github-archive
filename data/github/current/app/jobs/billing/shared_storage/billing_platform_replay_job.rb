# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  module SharedStorage
    class BillingPlatformReplayJob < BatchedJob

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      queue_as :billing_platform_replay

      def process_batch(batch, *args, **options)
        return unless GitHub.flipper[:billing_platform_replay].enabled?
        batch.each do |artifact|
          handle_artifact_addition(artifact: artifact, customer_id: options[:customer_id], owner_id: options[:owner_id])
        end
      end

      def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
        Artifact.
          includes(:check_suite).
          where(repository_id: options[:repository_id]).
          where("id > ?", offset_item_id).
          limit(BATCH_SIZE).
          order(:id, name: :asc)
      end

      private

      def handle_artifact_addition(artifact:, customer_id:, owner_id:)
        return if artifact.size.to_i.zero?
        return if artifact.expires_at && artifact.expires_at < launch_date

        usage_uuid_unique_id = "Actions/#{artifact.id}/add"
        is_dynamic, app_name, slug = get_dynamic_workflow(artifact)
        return if is_dynamic && skippable_dynamic_workflow?(app_name)

        size_in_gib = artifact.size.fdiv(1.gigabyte)
        # If the artifact was created before the launch of Billing Platform then we can just use the original
        # launch date. Billing Platform is really only concerened with whether or not the `usage_at` is today in order
        # to partially bill for usage. Using the launch date for earlier artifacts prevents us from creating a whole bunch
        # of rollups in the past.
        usage_at = artifact.created_at < launch_date ? launch_date : artifact.created_at

        usage_message = {
          sku: "actions_storage",
          quantity: size_in_gib,
          usage_at: usage_at,
          source_uri: artifact.to_global_id.to_s,
          usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, usage_uuid_unique_id), # rubocop:disable GitHub/InsecureHashAlgorithm
          entity: {
            customer_id: customer_id,
            organization_id: owner_id,
            repo_id: artifact.repository_id,
          },
        }

        result = Hydro::PublishRetrier.publish(usage_message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)
        if result.error
          GitHub.logger.error(
            "Failed to replay usage message to billing platform",
            {
              "artifact_id" => artifact.id,
              "repository_id" => artifact.repository_id,
              "error.class" => result.error.class,
            }
          )
          return
        end

        GitHub.dogstats.increment("actions.shared_storage.replay_usage")
      end

      def get_dynamic_workflow(artifact)
        ::Actions::Workflow.extract_dynamic_workflowfile_path(artifact.check_suite&.workflow_file_path)
      end

      def skippable_dynamic_workflow?(app_name)
        app_name == "pages" || app_name == "dependabot"
      end

      def launch_date
        Customer::BILLING_PLATFORM_ACTIONS_ROLLOUT_DATE.beginning_of_day
      end
    end
  end
end
