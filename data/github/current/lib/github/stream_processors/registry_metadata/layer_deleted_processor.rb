
# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class LayerDeletedProcessor < SingleMessageProcessor
        include CommonMethods

        default_to_write_connection!

        DEFAULT_GROUP_ID = "rms_layer_deleted"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.LayerDeleted\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 1.megabyte
        options[:start_from_beginning] = false

        # Initialize the LayerDeletedProcessor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.dead_letter_topic = "registry_metadata.v0.LayerDeleted.DeadLetter"
        end

        # TODO: Use PackagesArtifactStorageEvent whenever we enable billing for GHCR
        # And remove this

        # Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          # Part of Estimated billing Epic for packages https://github.com/github/package-registry-team/issues/4356
          # The feature flag check scoped to the owner used to be much lower in the code once we got the owner but this stream processor was having issues keeping up
          # Check for feature flag before processing the message without scoping to owner as a quick mitigation instead of fully removing this processor
          return message.skip("feature_flag_disabled") unless FeatureFlag.vexi.enabled?(:container_registry_billing, default: false)

          req_context = message.value.dig(:request_context)

          with_context(req_context) do
            trace_processor(self, req_context) do
              owner_id = message.value.dig(:owner_id).to_i
              return message.skip("blank_owner_id") if owner_id&.zero?

              owner = with_read do
                User.find_by(id: owner_id)
                &.tap do |user|
                  user.billable_owner
                end
              end
              return message.skip("missing_owner") if owner.nil?

              billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(owner)
              billable_owner = billable_owner_designator.billable_owner

              size_in_bytes = message.value.dig(:layer, :size)
              return message.skip("zero_size") if size_in_bytes.to_i.zero?

              ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry(max_retry_count: 5) do
                safe_trigger_heartbeat
                ::Billing::SharedStorage::ArtifactEvent.create!(
                  owner_id: owner_id,
                  repository_id: nil,
                  effective_at: Time.at(message.value.dig(:deleted_at, :seconds)),
                  source: :ghcr,
                  repository_visibility: :private,
                  event_type: :remove,
                  size_in_bytes: size_in_bytes,
                  source_artifact_id: nil,
                )
              end
            end
          end
        end

        private

        def trace_processor(processor, request_context)
          # TODO: Remove once https://github.com/github/github/pull/255604 is merged
          GitHub.tracer.in_span(processor.class.name.demodulize, kind: :consumer) do |_span|
            yield
          end
        end

        def error_context_for_message(message)
          super(message).merge({
            user_id: message.value.dig(:actor_id),
            layer: message.value.dig(:layer, :digest)
          })
        end
      end
    end
  end
end
