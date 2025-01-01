# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class PackageFilePublishedProcessor < SingleMessageProcessor

        default_to_write_connection!

        include TransientErrorResiliency

        self.slack_pause_notifications_channel = "#billing-alerts"

        DEFAULT_GROUP_ID = "package_file_published_processor"
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageFilePublished\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 100.kilobytes
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        # Initialize the PackageFilePublishedProcessor
        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.dead_letter_topic = "package_registry.v0.PackageFilePublished.DeadLetter"
        end

        # Create a Billing::SharedStorage::ArtifactEvent for the message
        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          registry_type = message.value.dig(:package, :registry_type)
          if registry_type == :DOCKER
            return message.skip("docker")
          end

          owner_id = message.value.dig(:package, :owner_id).to_i
          if owner_id == 0
            return message.skip("blank_owner_id")
          end

          user = with_read do
            User.find_by(id: owner_id)
            &.tap do |user|
              user.owner.billable_owner
            end
          end

          if user.nil?
            return message.skip("missing_owner")
          end

          size_in_bytes = message.value.dig(:file, :size)
          if size_in_bytes.to_i.zero?
            return message.skip("zero_size")
          end

          if [:NPM, :NUGET, :RUBYGEMS].include?(registry_type.to_sym)
            ms = ActiveRecord::Base.connected_to(role: :reading) do
              Registry::PackageVersion.where(id: message.value.dig(:version, :id)).pluck(:migration_state).first
            end
            return message.skip("migrated_version") if ms == "complete"
          end

          billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(user)
          billable_owner = billable_owner_designator.billable_owner

          source_artifact_id = message.value.dig(:version, :id)

          event_id = message.value.dig(:request_context, :request_id)
          # non unique event id prevents billing so if event_id is blank we set it to a random uuid
          event_id = SecureRandom.uuid if event_id.blank?

          size_in_gib = size_in_bytes.fdiv(1.gigabyte)

          usage = {
            sku: "packages_storage",
            quantity: size_in_gib,
            usage_at: Time.at(message.value.dig(:published_at, :seconds)),
            source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/source_artifact_id/#{source_artifact_id}",
            usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, event_id), # rubocop:disable GitHub/InsecureHashAlgorithm
            entity: {
              customer_id: billable_owner.feature_flag_enabled?(:use_find_or_create_customer, default: true) ? billable_owner.find_or_create_customer.id : (billable_owner.customer&.id || 0),
              repo_id: message.value.dig(:package, :repository, :id),
              # We must only populate organization_id if the package owner is an organization.
              organization_id: user.organization? ? owner_id : nil,
            }
          }

          result = Hydro::PublishRetrier.publish(usage, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

          if result.error
            GitHub.logger.error("Failed to publish vNext billing event",
              "gh.registry.message.owner_id" => owner_id,
              "gh.registry.message.repository_id" => message.value.dig(:package, :repository, :id),
              "gh.registry.message.source_artifact_id" => message.value.dig(:version, :id),
            )
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).returns(String) }
        def repository_visibility(message)
          case message.value.dig(:package, :repository, :visibility)
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
              user_id: message.value.dig(:package, :owner_id),
              repo_id: message.value.dig(:package, :repository, :id),
              package_id: message.value.dig(:package, :id),
          })
        end
      end
    end
  end
end
