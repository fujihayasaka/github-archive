# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Actions
      class ArtifactStorageEventProcessor < BaseProcessor

        default_to_write_connection!

        include TransientErrorResiliency

        self.slack_pause_notifications_channel = "#billing-alerts"

        BILLING_PLATFORM_STORAGE_ROLLOUT_DATE = T.let(DateTime.new(2023, 8, 23, 0, 0, 0).utc, Time)
        DEFAULT_GROUP_ID = "artifact_storage_event_processor"
        DEFAULT_SUBSCRIBE_TO = /github\.actions\.v0\.ArtifactStorageEvent\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 100.kilobytes
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        # Initialize the ArtifactStorageEventProcessor
        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.dead_letter_topic = "github.actions.v0.ArtifactStorageEvent.DeadLetter"
        end

        resolve_tenant_context do |message|
          Repositories::Public.resolve_tenant(id: message.value.dig(:artifact_repository_id))
        end

        # Handle the ArtifactStorageEvent message and create the necessary
        # Billing::SharedStorage::ArtifactEvent records
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
          artifact_id = message.value.dig(:artifact_id)
          if artifact_id.to_i.zero?
            GitHub.logger.info("Skipping artifact storage event with zero artifact_id")
            return message.skip("no_artifact_id")
          end

          size_in_bytes = message.value.dig(:artifact_size_in_bytes)
          if size_in_bytes.to_i.zero?
            GitHub.logger.info(
              "Skipping artifact storage event with zero size",
              { "artifact_id" => artifact_id }
            )
            return message.skip("zero_size")
          end

          GitHub.tracer.in_span("#{self.class.name}##{__method__}") do |_span|
            case message.value.dig(:artifact_event_type)
            when :ADD
              handle_artifact_addition(message)
            when :REMOVE
              handle_artifact_removal(message)
            when :EXPIRED
              handle_artifact_expiration(message)
            else
              message.skip("unknown_event_type")
            end
          end
        end

        private

        sig { params(message: GitHub::StreamProcessors::Message, owner: ::Billing::Types::Account, repo: T.nilable(Repository)).void }
        def send_to_billing_platform(message, owner, repo)
          return unless GitHub.flipper[:actions_shared_storage_use_billing_platform].enabled?(repo)

          artifact_id = message.value.dig(:artifact_id)
          usage_uuid_unique_id = "Actions/#{artifact_id}/"
          event_type = message.value.dig(:artifact_event_type)
          repository_id = message.value.dig(:artifact_repository_id)
          dd_tags = ["service:billing_platform"]

          # Only send to billing platform if the artifact was created after the rollout date
          if message.value.dig(:created_at) && Time.at(message.value.dig(:created_at, :seconds)) < BILLING_PLATFORM_STORAGE_ROLLOUT_DATE
            return
          end

          case event_type
          when :ADD
            usage_uuid_unique_id << "add"
            dd_tags << "event_type:add"
          when :REMOVE
            usage_uuid_unique_id << "remove"
            dd_tags << "event_type:remove"
          when :EXPIRED
            usage_uuid_unique_id << "remove"
            dd_tags << "event_type:expired"
          else
            return
          end

          is_dynamic, app_name, _ = get_dynamic_workflow_from_message(message)
          if is_dynamic && skippable_dynamic_workflow?(app_name.to_s)
            dd_tags << "dynamic_workflow_skipped:true"
            GitHub.dogstats.increment("actions.shared_storage.usage", tags: dd_tags)
            GitHub.logger.info(
              "Skipping artifact storage event with dynamic workflow",
              {
                "artifact_id" => artifact_id,
                "repository_id" => repository_id,
                "app_name" => app_name,
              }
            )
            return
          end

          owner_id = message.value.dig(:artifact_repository_owner_id)
          size_in_bytes = message.value.dig(:artifact_size_in_bytes)
          global_id = message.value.dig(:artifact_global_id)

          size_in_gib = size_in_bytes.fdiv(1.gigabyte)
          quantity = event_type == :ADD ? size_in_gib : -size_in_gib # negative for removal

          usage_message = {
            sku: "actions_storage",
            quantity: quantity,
            usage_at: Time.at(message.timestamp),
            source_uri: global_id,
            usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, usage_uuid_unique_id), # rubocop:disable GitHub/InsecureHashAlgorithm
            entity: {
              customer_id: owner.feature_enabled?(:use_find_or_create_customer) ? owner.find_or_create_customer.id : customer_for(owner),
              organization_id: owner_id,
              repo_id: repository_id,
            },
          }

          result = Hydro::PublishRetrier.publish(usage_message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)
          if result.error
            GitHub.logger.error(
              "Failed to publish usage message to billing platform",
              {
                "artifact_id" => artifact_id,
                "repository_id" => repository_id,
                "error.class" => result.error.class,
              }
            )
            return
          end

          GitHub.dogstats.increment("actions.shared_storage.usage", tags: dd_tags)
        end

        sig { params(owner: ::Billing::Types::Account).returns(T.nilable(Integer)) }
        def customer_for(owner)
          if owner.delegate_billing_to_business?
            T.cast(owner, User).business.customer_id
          else
            owner.customer&.id
          end
        end

        sig do
          params(
            message: GitHub::StreamProcessors::Message
          ).returns(T.any([T::Boolean, T.nilable(String), T.nilable(String)], T::Boolean))
        end
        def get_dynamic_workflow_from_message(message)
          check_suite_id = message.value.dig(:check_suite_id)
          check_suite = with_read do
            CheckSuite.find_by(id: check_suite_id)
          end
          ::Actions::Workflow.extract_dynamic_workflowfile_path(check_suite&.workflow_file_path)
        end

        sig { params(app_name: String).returns(T::Boolean) }
        def skippable_dynamic_workflow?(app_name)
          app_name == "pages" || app_name == "dependabot"
        end

        sig { params(message: GitHub::StreamProcessors::Message, app: String).returns(T::Boolean) }
        def skip_dynamic_workflow?(message, app)
          is_dynamic, app_name, _ = get_dynamic_workflow_from_message(message)
          return app_name == app if is_dynamic
          false
        end

        # Create one or more Billing::SharedStorage::ArtifactEvents for an
        # artifact addition message
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def handle_artifact_addition(message)
          artifact_id = message.value.dig(:artifact_id)
          size_in_bytes = message.value.dig(:artifact_size_in_bytes)
          owner_id = message.value.dig(:artifact_repository_owner_id)
          repository_id = message.value.dig(:artifact_repository_id)
          repository_visibility = repository_visibility(message)

          if owner_id.to_i.zero?
            return message.skip("blank_owner_id")
          end

          owner = with_read do
            User.find_by(id: owner_id)
            &.tap do |user|
              user.billable_owner
            end
          end
          if owner.nil?
            return message.skip("missing_owner")
          end

          repo = with_read { Repository.find_by(id: repository_id) }

          send_to_billing_platform(message, owner, repo)

          return if GitHub.flipper[:actions_shared_storage_skip_meuse].enabled?(repo)

          GitHub.dogstats.increment("actions.shared_storage.usage", tags: ["event_type:add", "service:meuse"])

          ActiveRecord::Base.connected_to(role: :reading) do
            return message.skip("skip_storage_dynamic_workflow_pages") if skip_dynamic_workflow?(message, "pages")
          end

          artifact_addition_exists = with_read do
            ::Billing::SharedStorage::ArtifactEvent
              .actions_source
              .add_event
              .where(
                owner_id: owner.id,
                repository_id: repository_id,
                source_artifact_id: artifact_id,
                size_in_bytes: size_in_bytes
              )
              .exists?
          end

          if artifact_addition_exists
            return message.skip("artifact_addition_exists")
          end

          base_attributes = {
            owner_id: owner.id,
            repository_id: repository_id,
            source: :actions,
            repository_visibility: repository_visibility,
            size_in_bytes: size_in_bytes,
            source_artifact_id: artifact_id,
          }

          events = []
          events << base_attributes.merge(
            effective_at: Time.at(message.timestamp),
            event_type: :add,
          )

          # If the artifact expires, record a remove event effective in the future
          if message.value.dig(:expires_at)
            events << base_attributes.merge(
              effective_at: Time.at(message.value.dig(:expires_at, :seconds)),
              event_type: :remove,
            )
          end

          ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry(max_retry_count: 5) do
            safe_trigger_heartbeat
            # Using transaction as ActiveRecord#create!(Array) results in multiple insert statements
            ::Billing::SharedStorage::ArtifactEvent.transaction do
              ::Billing::SharedStorage::ArtifactEvent.create!(events)
            end
          end
        end

        # Create a Billing::SharedStorage::ArtifactEvents for an artifact
        # removal message and update any future messages as needed
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def handle_artifact_removal(message)
          # Most/All artifacts auto-expire and have a future dated removal event
          # created at the same time as the creation event.
          # We start by looking for that already created removal event

          artifact_id = message.value.dig(:artifact_id)
          repository_id = message.value.dig(:artifact_repository_id)

          repo = with_read { Repository.find_by(id: repository_id) }
          owner_id = message.value.dig(:artifact_repository_owner_id)
          if !owner_id.to_i.zero?
            owner = with_read do
              User.find_by(id: owner_id)
              &.tap do |user|
                user.billable_owner
              end
            end

            if !owner.nil?
              send_to_billing_platform(message, owner, repo)
            end
          end
          return if GitHub.flipper[:actions_shared_storage_skip_meuse].enabled?(repo)

          GitHub.dogstats.increment("actions.shared_storage.usage", tags: ["event_type:remove", "service:meuse"])

          existing_removal = with_read do
            ::Billing::SharedStorage::ArtifactEvent
              .actions_source
              .remove_event
              .where(
                source_artifact_id: artifact_id,
              ).order(:id).last
          end

          if existing_removal
            # If the removal has an effective date at the same time as the message being processed
            # then we are almost certainly reprocessing the same message, so skip re-processing
            if existing_removal.effective_at.to_i == message.timestamp.to_i
              return message.skip("artifact_removal_exists")
            end

            # If the existing removal is effective later than this message, and not yet aggregated,
            # We can just move forward the effective date of the existing removal to the time of the message
            # and be done
            if existing_removal.aggregation_id.nil? && existing_removal.effective_at > Time.at(message.timestamp)
              log_mismatch_if_needed(message, existing_removal)
              ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry(max_retry_count: 5) do
                safe_trigger_heartbeat
                existing_removal.update!(effective_at: Time.at(message.timestamp))
              end
              return
            end
          end

          # If the existing removal is in the past, the artifact either automatically expired
          # in which case we can ignore the message or the removal is from the transfer out of a previous owner.
          # We handle both cases by looking for any unbalanced adds/removes

          # If every add event has a remove event, then the artifact already expired and we can skip the message
          # But if there is an add without a remove, then we need to create the remove event

          distinct_owner_events = with_read do
            ::Billing::SharedStorage::ArtifactEvent
              .actions_source
              .where(source_artifact_id: artifact_id)
              .group(:owner_id, :event_type)
              .select(:owner_id, :event_type)
              .distinct
              .reduce({}) do |acc, event|
                acc[event.owner_id] ||= []
                acc[event.owner_id] << event.event_type
                acc
              end
          end

          owner_needing_removal = distinct_owner_events.reject do |_owner_id, event_types|
            event_types.include?("remove")
          end.keys.first

          if owner_needing_removal.nil?
            return message.skip("no_removal_needed")
          end

          # We should rarely get to this point, but apparently the artifact didn't have an expiration removal
          # event that we could find, so we'll create a new removal event.

          # Most removal events happen after a repo is deleted, so the event might not have any owner info
          # We can look up all the info needed from the creation event based on the artifact id

          creation_event = with_read do
            ::Billing::SharedStorage::ArtifactEvent
              .actions_source
              .add_event
              .find_by!(
                owner_id: owner_needing_removal,
                source_artifact_id: artifact_id,
              )
          end

          new_removal_event = ::Billing::SharedStorage::ArtifactEvent.new(
            owner_id: creation_event.owner_id,
            repository_id: creation_event.repository_id,
            source: :actions,
            repository_visibility: creation_event.repository_visibility,
            event_type: :remove,
            size_in_bytes: message.value.dig(:artifact_size_in_bytes),
            effective_at: Time.at(message.timestamp),
            source_artifact_id: artifact_id,
          )

          log_mismatch_if_needed(message, creation_event)

          ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry(max_retry_count: 5) do
            safe_trigger_heartbeat
            ::Billing::SharedStorage::ArtifactEvent.transaction do
              new_removal_event.save!
            end
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def handle_artifact_expiration(message)
          owner_id = message.value.dig(:artifact_repository_owner_id)
          repository_id = message.value.dig(:artifact_repository_id)
          artifact_id = message.value.dig(:artifact_id)

          if owner_id.to_i.zero?
            GitHub.logger.info("Skipping artifact expiration with blank owner_id", { "artifact_id" => artifact_id, "repository_id" => repository_id })
            return message.skip("blank_owner_id")
          end

          owner = with_read do
            User.find_by(id: owner_id)
            &.tap do |user|
              user.billable_owner
            end
          end
          if owner.nil?
            GitHub.logger.info("Skipping artifact expiration with nil owner", { "artifact_id" => artifact_id, "repository_id" => repository_id })
            return message.skip("missing_owner")
          end

          repo = with_read { Repository.find_by(id: repository_id) }
          send_to_billing_platform(message, owner, repo)
        end

        sig { params(message: GitHub::StreamProcessors::Message, artifact_event: ::Billing::SharedStorage::ArtifactEvent).void }
        def log_mismatch_if_needed(message, artifact_event)
          owner_id = message.value.dig(:artifact_repository_owner_id)
          repository_id = message.value.dig(:artifact_repository_id)

          if !owner_id.zero?
            if artifact_event.owner_id != owner_id || artifact_event.repository_id != repository_id
              GitHub.logger.info(
                "artifact_removal_owner_repository_mismatch",
                "gh.processor.message.id" => message.respond_to?(:id) ? message.id : nil,
                "gh.billing.artifact.repository_owner.id" => owner_id,
                "gh.billing.artifact.repository.id" => repository_id,
                "gh.billing.artifact.event.id" => artifact_event.id,
                "gh.billing.artifact.event.owner.id" => artifact_event.owner_id,
                "gh.billing.artifact.event.repository.id" => artifact_event.repository_id,
              )
            end
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).returns(String) }
        def repository_visibility(message)
          case message.value.dig(:artifact_repository_visibility)
          when :VISIBILITY_UNKNOWN
            "unknown"
          when :PUBLIC
            "public"
          when :PRIVATE
            "private"
          when :INTERNAL
            "private"
          else
            "unknown"
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).returns(T::Hash[T.any(String, Symbol), T.untyped]) }
        def error_context_for_message(message)
          super(message).merge({
            artifact_id: message.value.dig(:artifact_id),
            user_id: message.value.dig(:artifact_repository_owner_id),
            repo_id: message.value.dig(:artifact_repository_id),
          })
        end
      end
    end
  end
end
