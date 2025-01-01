# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class PackageTransferredProcessor < SingleMessageProcessor

        default_to_write_connection!

        include TransientErrorResiliency

        self.slack_pause_notifications_channel = "#billing-alerts"

        DEFAULT_GROUP_ID = "package_transferred_processor"
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageTransferred\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 100.kilobytes
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        # Initialize the PackageTransferredProcessor
        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.dead_letter_topic = "package_registry.v0.PackageTransferred.DeadLetter"
        end

        # Create Billing::SharedStorage::ArtifactEvent records for the message
        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          if ::FeatureFlag.vexi.enabled?(:packages_fix_maven_billing_issue, default: false)
            old_owner_id = message.value.dig(:previous_owner_id).to_i
            if old_owner_id == 0
              return message.skip("missing_old_owner_id")
            end

            old_user = with_read do
              User.find_by(id: old_owner_id)
              &.tap do |user|
                user.owner.billable_owner
              end
            end

            if old_user.nil?
              return message.skip("missing_old_owner")
            end

            old_billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(old_user)
            old_billable_owner = old_billable_owner_designator.billable_owner

            effective_at = Time.at(message.value.dig(:transferred_at, :seconds))
            size_in_bytes = message.value.dig(:package, :total_size, :value)
            size_in_gib = size_in_bytes.fdiv(1.gigabyte)
            if size_in_bytes.to_i.zero?
              return message.skip("zero_size")
            end

            # When the repo itself is transferred, .previous_repository is null
            previous_repository = message.value.dig(:previous_repository) ||
              message.value.dig(:package, :repository) || {}

            source_artifact_id = message.value.dig(:package, :id)

            event_id = message.value.dig(:request_context, :request_id)
            # non unique event id prevents billing so if event_id is blank we set it to a random uuid
            event_id = SecureRandom.uuid if event_id.blank?

            usage_uuid_1 = Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, event_id) # rubocop:disable GitHub/InsecureHashAlgorithm
            usage_uuid_2 = SecureRandom.uuid

            usage = {
              sku: "packages_storage",
              quantity: -size_in_gib,
              usage_at: effective_at,
              source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/source_artifact_id/#{source_artifact_id}",
              usage_uuid: usage_uuid_1,
              entity: {
                customer_id: old_billable_owner.feature_flag_enabled?(:use_find_or_create_customer, default: true) ? old_billable_owner.find_or_create_customer.id : (old_billable_owner.customer&.id || 0),
                repo_id: previous_repository[:id],
                # We must only populate organization_id if the package owner is an organization.
                organization_id: old_user.organization? ? old_owner_id : nil,
              }
            }

            result = Hydro::PublishRetrier.publish(usage, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

            if result.error
              GitHub.logger.error("Failed to publish vNext billing event",
                "gh.registry.message.owner_id" => old_owner_id,
                "gh.registry.message.repository_id" => previous_repository[:id],
                "gh.registry.message.source_artifact_id" => source_artifact_id,
              )
            end

            new_repository_id = message.value.dig(:package, :repository, :id)

            new_owner_id = message.value.dig(:package, :owner_id).to_i
            if new_owner_id == 0
              return message.skip("missing_new_owner_id")
            end

            new_user = with_read do
              User.find_by(id: new_owner_id)
              &.tap do |user|
                user.owner.billable_owner
              end
            end

            if new_user.nil?
              return message.skip("missing_new_owner")
            end

            new_billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(new_user)
            new_billable_owner = new_billable_owner_designator.billable_owner

            usage = {
              sku: "packages_storage",
              quantity: size_in_gib,
              usage_at: effective_at,
              source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/source_artifact_id/#{source_artifact_id}",
              usage_uuid: usage_uuid_2,
              entity: {
                customer_id: new_billable_owner.feature_flag_enabled?(:use_find_or_create_customer, default: true) ? new_billable_owner.find_or_create_customer.id : (new_billable_owner.customer&.id || 0),
                repo_id: new_repository_id,
                # We must only populate organization_id if the package owner is an organization.
                organization_id: new_user.organization? ? new_owner_id : nil,
              }
            }

            result = Hydro::PublishRetrier.publish(usage, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

            if result.error
              GitHub.logger.error("Failed to publish vNext billing event",
                "gh.registry.message.owner_id" => new_owner_id,
                "gh.registry.message.repository_id" => new_repository_id,
                "gh.registry.message.source_artifact_id" => source_artifact_id,
              )
            end

          else
            new_owner_id = message.value.dig(:package, :owner_id).to_i
            if new_owner_id == 0
              return message.skip("missing_new_owner")
            end

            old_owner_id = message.value.dig(:previous_owner_id).to_i
            if old_owner_id == 0
              return message.skip("missing_old_owner")
            end

            # Will raise if the old owner has been destroyed.
            # This is tested and will be reported to sentry
            with_read { User.find(old_owner_id) }

            effective_at = Time.at(message.value.dig(:transferred_at, :seconds))
            size_in_bytes = message.value.dig(:package, :total_size, :value)

            # When the repo itself is transferred, .previous_repository is null
            previous_repository = message.value.dig(:previous_repository) ||
              message.value.dig(:package, :repository) || {}

            ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry(max_retry_count: 5) do
              safe_trigger_heartbeat
              # Using transaction as ActiveRecord#create!(Array) results in multiple insert statements
              ::Billing::SharedStorage::ArtifactEvent.transaction do
                ::Billing::SharedStorage::ArtifactEvent.create!(
                  [
                    {
                      owner_id: message.value.dig(:previous_owner_id).to_i,
                      repository_id: previous_repository[:id],
                      effective_at: effective_at,
                      source: :gpr,
                      repository_visibility: repository_visibility(previous_repository[:visibility]),
                      event_type: :remove,
                      size_in_bytes: size_in_bytes,
                    },
                    {
                      owner_id: message.value.dig(:package, :owner_id).to_i,
                      repository_id: message.value.dig(:package, :repository, :id),
                      effective_at: effective_at,
                      source: :gpr,
                      repository_visibility: repository_visibility(message.value.dig(:package, :repository, :visibility)),
                      event_type: :add,
                      size_in_bytes: size_in_bytes,
                    },
                  ],
                )
              end
            end
          end
        end

        sig { params(value: Symbol).returns(String) }
        def repository_visibility(value)
          case value
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

        private

        sig { params(message: GitHub::StreamProcessors::Message).returns(T::Hash[T.any(Symbol, String), T.untyped]) }
        def error_context_for_message(message)
          super(message).merge({
            package_id: message.value.dig(:package, :id),
            user_id: message.value.dig(:package, :owner_id),
            repo_id: message.value.dig(:package, :repository, :id),
          })
        end
      end
    end
  end
end
