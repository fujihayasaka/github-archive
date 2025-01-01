
# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class LayerDownloadedProcessor < BaseProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = "rms_layer_downloaded"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.LayerDownloaded\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 1.megabytes
        options[:start_from_beginning] = false

        # Initialize the LayerDownloadedProcessor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.dead_letter_topic = "registry_metadata.v0.LayerDownloaded.DeadLetter"
        end

        # Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          # Part of Estimated billing Epic for packages https://github.com/github/package-registry-team/issues/4356
          # The feature flag check scoped to the owner used to be much lower in the code once we got the owner but this stream processor was having issues keeping up
          # Check for feature flag before processing the message without scoping to owner as a quick mitigation instead of fully removing this processor
          return message.skip("feature_flag_disabled") unless GitHub.flipper[:container_registry_billing].enabled?

          req_context = message.value.dig(:request_context)

          initialize_context(req_context)
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

            GitHub.logger.info(
              "Billing Message Received",
              "code.namespace" => self.class.name,
              "code.function" => "#process_message",
              "gh.registry.message.type" => "layer_downloaded",
              "gh.registry.message.actor.type" => message.value.dig(:actor_type),
              "gh.registry.message.actor_id" => message.value.dig(:actor_id),
              "gh.registry.message.owner_id" => message.value.dig(:owner_id),
              "gh.registry.message.package_id" => 0, # No package_id in the message. See call to `DataTransferLineItemCreator` bellow.
            )

            # We must not pass the actor_id if it's not a user.
            # Reporting uses the actor_id to determine the user who performed the action.
            # Passing it in case of an installation will result in random user names showing up in the report.
            # Codespaces can pull packages during pre-builds, which are not associated with a user.
            # A user using Codespaces is also using the same token type. It might be possible to identify the `user_id` in this case.
            # However, we haven't found a way to do so yet. For now, we are not associating any Codespace requests with users.
            actor_id = if message.value.dig(:actor_type) == :ACTOR_TYPE_USER
              message.value.dig(:actor_id).to_i
            else
              nil
            end

            size_in_bytes = message.value.dig(:layer, :size)
            return message.skip("zero_size") if size_in_bytes.to_i.zero?

            billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(owner)
            billable_owner = billable_owner_designator.billable_owner
            with_read do
              if billable_owner.skip_metered_billing_permission_check_for?(product: :packages)
                return message.skip("metered_permissions_skipped")
              end
            end

            return message.skip("billable_owner_skips_cr_billing") if GitHub.flipper[:packages_skip_cr_billing].enabled?(billable_owner)

            # As of https://github.com/github/gitcoin/issues/19652,
            # we'll no be billing via Meuse anymore.
            # Whenever we want to start billing for Container Registry downloads,
            # we should do so with Billing Platform as is done in
            # lib/github/stream_processors/package_version_downloaded_processor.rb
            # and lib/github/stream_processors/registry_metadata/version_downloaded_processor.rb
            unless ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
              ::Billing::PackageRegistry::DataTransferLineItemCreator.create(
                owner: owner,
                actor_id: actor_id,
                registry_package_id: 0, # this is what gitcoin suggests
                registry_package_version_id: 0, # ditto
                name: message.value.dig(:package, :name), # name is not present in the message. Needs to be added when CR billing is enabled.
                size_in_bytes: message.value.dig(:layer, :size),
                download_id: message.value[:event_id],
                downloaded_at: downloaded_at(message),
                source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/event_id/#{message.value[:event_id]}"
              )
            end
          end
        end

        def downloaded_at(message)
          message_seconds = message.value.dig(:downloaded_at, :seconds)
          if message_seconds.present?
            Time.at(message_seconds)
          else
            Time.now.utc
          end
        end

        private

        def initialize_context(request_context)
          GitHub.context.push({
            actor_ip: request_context.dig(:x_real_ip),
            request_id: request_context.dig(:request_id)
          })
        end

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
