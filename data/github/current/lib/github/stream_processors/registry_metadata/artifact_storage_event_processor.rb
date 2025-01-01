# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class ArtifactStorageEventProcessor < BaseProcessor
        # This provides resiliency to transient errors by initially retrying
        # transient errors before briefly pausing the processor when the retries
        # are exhausted. The duration of the pause can be configuerd via the
        # transient_error_pause_duration field on the processor instance
        include TransientErrorResiliency
        include CommonMethods

        self.slack_pause_notifications_channel = "#billing-alerts"

        DEFAULT_GROUP_ID = "github-#{Rails.env}-registry_metadata-artifact_storage_event_processor"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.PackagesArtifactStorageEvent\Z/

        # This is the timeout used for determining if a given Kafka consumer has
        # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
        # recommended if your Hydro processor interacts with the database, since
        # Freno may wait up to 30 seconds when throttling writes. Processors that
        # do not interact with a database may lower this value to allow faster
        # consumer group rebalancing during deploys and processor failures.
        #
        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 60.seconds

        # This value must be greater than "session_timeout"
        #
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 65.seconds

        # When the processor starts consuming from a partition for the first time and has no committed offsets,
        # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
        # or the end of the log (i.e. the newest available messages).
        #
        # This is the equivalent of the java client `auto.offset.reset` consumer config.
        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = false

        # Other options you may want to set...
        #
        # This will cause the Kafka consumer to wait until there is at least a
        # given number of bytes available to fetch; but the consumer will wait
        # no longer than "max_wait_time" (described below). This allows the
        # processor to wait for a large enough batch of data. The default is
        # 1 byte, meaning data will be fetched as soon as it's available. Value
        # below is for example purposes only and not a recommendation; the default
        # value of 1 should be suitable for most cases.
        # See https://kafka.apache.org/documentation/#fetch.min.bytes
        # options[:min_bytes] = 1.kilobyte
        #
        # This is the maximum amount of time the Kafka consumer will wait to
        # fetch data. The default is 500ms (0.5.seconds). Value below is for
        # example purposes only and not a recommendation; the default value of
        # 500ms should be suitable for most cases.
        # options[:max_wait_time] = 1.second
        #
        # This is the maximum amount of data that will be fetched at a time. This
        # value is specified in bytes, so the number of distinct Hydro messages
        # fetched depends on the size of those messages. The default is 1MB. You
        # may want to consider lowering this if processing each batch of messages
        # is taking more than 60 seconds in order to ensure that your processor
        # shuts down in a timely manner during deploys.
        # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
        # options[:max_bytes_per_partition] = 100.kilobytes

        # The processor queries for existing data using directly owner ID
        # thus we don't need to worry about tenant context.
        exempt_from_tenant_context_requirement

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          req_context = message.value.dig(:request_context)
          initialize_context(req_context)

          trace_processor(self, req_context) do
            ecosystem = message.value.dig(:package, :ecosystem).downcase.to_s

            # GHCR is not billed ( yet )
            return message.skip("container_package") if ecosystem == "container"

            # Check if ecosystem is billed
            unless RegistryTwo::MembersHelper::BILLED_V2_ECOSYSTEMS.include?(ecosystem)
              return message.skip("ecosystem_not_billed")
            end

            # Public packages are free :)
            return message.skip("public_package") if is_public_package?(message)

            # Cannot bill if owner_id is blank
            owner_id = message.value.dig(:owner_id).to_i
            return message.skip("blank_owner_id") if owner_id.zero?

            # Cannot bill if owner is not present
            owner = with_read do
              User.find_by(id: owner_id)
              &.tap do |user|
                user.billable_owner
              end
            end
            return message.skip("missing_owner") if owner.nil?

            # Do not bill if metered services billing is disabled for the owner
            billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(owner)
            billable_owner = billable_owner_designator.billable_owner
            if GitHub.flipper[:packages_skip_v2_billing].enabled?(billable_owner)
              return message.skip("billable_owner_skips_packages_v2_billing")
            end

            # Do not bill zero size
            size_in_bytes = message.value.dig(:artifact_storage_bytes)
            return message.skip("zero_size") if size_in_bytes.to_i.zero?

            event_type = case message.value.dig(:artifact_event_type)
            when :ADD
              :add
            when :REMOVE
              :remove
            else
              return message.skip("unknown_artifact_event_type")
            end

            if billable_owner.customer&.packages_billed_on_billing_platform?

              event_id = message.value.dig(:request_context, :request_id)
              # non unique event id prevents billing so if event_id is blank we set it to a random uuid
              event_id = SecureRandom.uuid if event_id.blank?


              # We must not pass the actor_id if it's not a user.
              # Reporting uses the actor_id to determine the user who performed the action.
              # Passing it in case of an installation will result in random user names showing up in the report.
              # Codespaces can pull packages during pre-builds, which are not associated with a user.
              # A user using Codespaces is also using the same token type. It might be possible to identify the `user_id` in this case.
              # However, we haven't found a way to do so yet. For now, we are not associating any Codespace requests with users.
              actor_id = actor_id(message)

              size_in_gib = size_in_bytes.fdiv(1.gigabyte)

              quantity = event_type == :add ? size_in_gib : -size_in_gib

              # emit billing event to vNext
              usage = {
                sku: "packages_storage",
                quantity: quantity,
                usage_at: Time.at(message.value.dig(:artifact_event_at, :seconds)),
                source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/event_id/#{event_id}",
                usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, event_id), # rubocop:disable GitHub/InsecureHashAlgorithm
                entity: {
                  customer_id: customer_id(owner),
                  actor_id: actor_id,
                }
              }

              result = Hydro::PublishRetrier.publish(usage, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

              if result.error
                GitHub.logger.error("Failed to publish vNext billing event",
                  "gh.registry.message.type" => "artifact_storage",
                  "gh.registry.message.owner_id" => owner_id,
                  "gh.registry.message.package_id" => message.value.dig(:package, :id),
                  "error.class" => result.error.class,
                )
                return
              end
            else
              artifact_event = {
                owner_id: owner_id,
                repository_id: nil,
                effective_at: Time.at(message.value.dig(:artifact_event_at, :seconds)),
                source: :packages_v2,
                repository_visibility: :private,
                event_type: event_type,
                size_in_bytes: size_in_bytes,
                source_artifact_id: message.value.dig(:version, :id),
              }

              with_write do
                ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry(max_retry_count: 5) do
                  safe_trigger_heartbeat
                  ::Billing::SharedStorage::ArtifactEvent.create!(artifact_event)
                end
              end
            end
          end
        end

        private

        def error_context_for_message(message)
          super(message).merge({
            request_id: message.value.dig(:request_context, :request_id),
            package_id: message.value.dig(:package, :id),
            namespace: message.value.dig(:package, :namespace),
            name: message.value.dig(:package, :name),
            version_id: message.value.dig(:version, :id),
            version: message.value.dig(:version, :name),
          })
        end
      end
    end
  end
end
