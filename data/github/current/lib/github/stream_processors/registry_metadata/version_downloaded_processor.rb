# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class VersionDownloadedProcessor < SingleMessageProcessor
        # TODO: default_to_write_connection
        include TransientErrorResiliency
        include CommonMethods

        self.slack_pause_notifications_channel = "#billing-alerts"

        DEFAULT_GROUP_ID = "rms_version_download_billing"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.VersionDownloadBilling\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 1.megabyte
        options[:start_from_beginning] = false

        # Initialize the IndexVersionDownloadedProcessor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          # TODO : Create a dead letter topic ?
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          req_context = message.value.dig(:request_context)

          if FeatureFlag.vexi.enabled?(:packages_fix_stream_processor_memory_leak, default: false)
            with_context(req_context) do
              trace_processor(self, req_context) do
                ecosystem = message.value.dig(:package, :ecosystem).downcase.to_s

                # Containers are billed through layer downloaded event
                return message.skip("container_package") if ecosystem == "container"

                # Check if ecosystem is billed
                if !RegistryTwo::MembersHelper::BILLED_V2_ECOSYSTEMS.include?(ecosystem)
                  return message.skip("ecosystem_not_billed")
                end

                # Do no bill public package
                return message.skip("public_package") if is_public_package?(message)

                # Do not bill access via actions token
                if message.value.dig(:actor_type) == :ACTOR_TYPE_INSTALLATION
                  return message.skip("github_token")
                end

                # Do not bill version downloads from Actions and Codespaces Prebuilds. If we were to add another site scoped integration installation this logic needs to be revisited.
                if message.value.dig(:actor_type) == :ACTOR_TYPE_SITE_SCOPED_INSTALLATION
                  return message.skip("site_scoped_installation")
                end

                # Do not bill for download from github hosted actions
                real_ip = req_context.dig(:x_real_ip)
                if real_ip.present? && ::GitHub.actions_runner_ips_include?(real_ip)
                  return message.skip("download_via_actions")
                end

                # Cannot bill if owner_id is blank
                owner_id = message.value.dig(:owner_id).to_i
                return message.skip("blank_owner_id") if owner_id&.zero?

                # Cannot bill if owner is not present
                owner = with_read do
                  User.find_by(id: owner_id)
                  &.tap do |user|
                    user.billable_owner
                  end
                end
                return message.skip("missing_owner") if owner.nil?

                billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(owner)
                billable_owner = billable_owner_designator.billable_owner

                # Do not bill if packages_skip_v2_billing is enabled for the billable owner
                if FeatureFlag.vexi.enabled?(:packages_skip_v2_billing, billable_owner, default: false)
                  return message.skip("billable_owner_skips_packages_v2_billing")
                end

                # Do not bill if metered services billing is disabled for the owner
                with_read do
                  if billable_owner.skip_metered_billing_permission_check_for?(product: :packages)
                    return message.skip("metered_permissions_skipped")
                  end
                end

                GitHub.logger.info(
                  "Billing Message Received",
                  "code.namespace" => self.class.name,
                  "code.function" => "#process_message",
                  "gh.registry.message.type" => "version_downloaded",
                  "gh.registry.message.actor_type" => message.value.dig(:actor_type),
                  "gh.registry.message.actor_id" => message.value.dig(:actor_id),
                  "gh.registry.message.owner_id" => message.value.dig(:owner_id),
                  "gh.registry.message.package_id" => message.value.dig(:package, :id),
                )

                # We must not pass the actor_id if it's not a user.
                # Reporting uses the actor_id to determine the user who performed the action.
                # Passing it in case of an installation will result in random user names showing up in the report.
                # Codespaces can pull packages during pre-builds, which are not associated with a user.
                # A user using Codespaces is also using the same token type. It might be possible to identify the `user_id` in this case.
                # However, we haven't found a way to do so yet. For now, we are not associating any Codespace requests with users.
                actor_id = actor_id(message)

                # Do not bill zero size
                size_in_bytes = message.value.dig(:storage_bytes)
                return message.skip("zero_size") if size_in_bytes.to_i.zero?

                event_id = message.value.dig(:request_context, :request_id)
                # non unique event id prevents billing so if event_id is blank we set it to a random uuid
                event_id = SecureRandom.uuid if event_id.blank?

                size_in_gib = size_in_bytes.fdiv(1.gigabyte)

                # We must only populate organization_id if the package owner is an organization.
                organization_id = organization_id(owner)

                usage = {
                  sku: "packages_bandwidth",
                  quantity: size_in_gib,
                  usage_at: downloaded_at(message),
                  source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/event_id/#{event_id}",
                  usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, event_id), # rubocop:disable GitHub/InsecureHashAlgorithm
                  entity: {
                    customer_id: owner.feature_flag_enabled?(:use_find_or_create_customer, default: true) ? owner.find_or_create_customer.id : customer_id(owner),
                    actor_id: actor_id,
                    organization_id: organization_id,
                  }
                }

                result = Hydro::PublishRetrier.publish(usage, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

                if result.error
                  GitHub.logger.error("Failed to publish vNext billing event",
                    "gh.registry.message.type" => "version_downloaded",
                    "gh.registry.message.actor_type" => message.value.dig(:actor_type),
                    "gh.registry.message.actor_id" => actor_id,
                    "gh.registry.message.owner_id" => message.value.dig(:owner_id),
                    "gh.registry.message.package_id" => message.value.dig(:package, :id),
                    "error.class" => result.error.class,
                  )
                  return
                end
              end
            end
          else
            initialize_context(req_context)
            trace_processor(self, req_context) do
              ecosystem = message.value.dig(:package, :ecosystem).downcase.to_s

              # Containers are billed through layer downloaded event
              return message.skip("container_package") if ecosystem == "container"

              # Check if ecosystem is billed
              if !RegistryTwo::MembersHelper::BILLED_V2_ECOSYSTEMS.include?(ecosystem)
                return message.skip("ecosystem_not_billed")
              end

              # Do no bill public package
              return message.skip("public_package") if is_public_package?(message)

              # Do not bill access via actions token
              if message.value.dig(:actor_type) == :ACTOR_TYPE_INSTALLATION
                return message.skip("github_token")
              end

              # Do not bill version downloads from Actions and Codespaces Prebuilds. If we were to add another site scoped integration installation this logic needs to be revisited.
              if message.value.dig(:actor_type) == :ACTOR_TYPE_SITE_SCOPED_INSTALLATION
                return message.skip("site_scoped_installation")
              end

              # Do not bill for download from github hosted actions
              real_ip = req_context.dig(:x_real_ip)
              if real_ip.present? && ::GitHub.actions_runner_ips_include?(real_ip)
                return message.skip("download_via_actions")
              end

              # Cannot bill if owner_id is blank
              owner_id = message.value.dig(:owner_id).to_i
              return message.skip("blank_owner_id") if owner_id&.zero?

              # Cannot bill if owner is not present
              owner = with_read do
                User.find_by(id: owner_id)
                &.tap do |user|
                  user.billable_owner
                end
              end
              return message.skip("missing_owner") if owner.nil?

              billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(owner)
              billable_owner = billable_owner_designator.billable_owner

              # Do not bill if packages_skip_v2_billing is enabled for the billable owner
              if FeatureFlag.vexi.enabled?(:packages_skip_v2_billing, billable_owner, default: false)
                return message.skip("billable_owner_skips_packages_v2_billing")
              end

              # Do not bill if metered services billing is disabled for the owner
              with_read do
                if billable_owner.skip_metered_billing_permission_check_for?(product: :packages)
                  return message.skip("metered_permissions_skipped")
                end
              end

              GitHub.logger.info(
                "Billing Message Received",
                "code.namespace" => self.class.name,
                "code.function" => "#process_message",
                "gh.registry.message.type" => "version_downloaded",
                "gh.registry.message.actor_type" => message.value.dig(:actor_type),
                "gh.registry.message.actor_id" => message.value.dig(:actor_id),
                "gh.registry.message.owner_id" => message.value.dig(:owner_id),
                "gh.registry.message.package_id" => message.value.dig(:package, :id),
              )

              # We must not pass the actor_id if it's not a user.
              # Reporting uses the actor_id to determine the user who performed the action.
              # Passing it in case of an installation will result in random user names showing up in the report.
              # Codespaces can pull packages during pre-builds, which are not associated with a user.
              # A user using Codespaces is also using the same token type. It might be possible to identify the `user_id` in this case.
              # However, we haven't found a way to do so yet. For now, we are not associating any Codespace requests with users.
              actor_id = actor_id(message)

              # Do not bill zero size
              size_in_bytes = message.value.dig(:storage_bytes)
              return message.skip("zero_size") if size_in_bytes.to_i.zero?

              event_id = message.value.dig(:request_context, :request_id)
              # non unique event id prevents billing so if event_id is blank we set it to a random uuid
              event_id = SecureRandom.uuid if event_id.blank?

              size_in_gib = size_in_bytes.fdiv(1.gigabyte)

              # We must only populate organization_id if the package owner is an organization.
              organization_id = organization_id(owner)

              usage = {
                sku: "packages_bandwidth",
                quantity: size_in_gib,
                usage_at: downloaded_at(message),
                source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/event_id/#{event_id}",
                usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, event_id), # rubocop:disable GitHub/InsecureHashAlgorithm
                entity: {
                  customer_id: owner.feature_flag_enabled?(:use_find_or_create_customer, default: true) ? owner.find_or_create_customer.id : customer_id(owner),
                  actor_id: actor_id,
                  organization_id: organization_id,
                }
              }

              result = Hydro::PublishRetrier.publish(usage, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

              if result.error
                GitHub.logger.error("Failed to publish vNext billing event",
                  "gh.registry.message.type" => "version_downloaded",
                  "gh.registry.message.actor_type" => message.value.dig(:actor_type),
                  "gh.registry.message.actor_id" => actor_id,
                  "gh.registry.message.owner_id" => message.value.dig(:owner_id),
                  "gh.registry.message.package_id" => message.value.dig(:package, :id),
                  "error.class" => result.error.class,
                )
                return
              end
            end
          end
        end

        def downloaded_at(message)
          message_seconds = message.value.dig(:time, :seconds)
          if message_seconds.present?
            Time.at(message_seconds)
          else
            Time.now.utc
          end
        end

        def package_id(message)
          message.value.dig(:package, :id)
        end

        def version_id(message)
          message.value.dig(:version, :id)
        end

        private

        def error_context_for_message(message)
          super(message).merge({
            user_id: message.value.dig(:actor_id),
            version_id: message.value.dig(:version, :id)
          })
        end
      end
    end
  end
end
