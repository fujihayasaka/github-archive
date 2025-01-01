# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class PackageVersionDownloadedProcessor < BaseProcessor
      extend T::Sig
      default_to_write_connection!

      include TransientErrorResiliency

      self.slack_pause_notifications_channel = "#billing-alerts"

      DEFAULT_GROUP_ID = "package_version_downloaded_processor"
      DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageVersionDownloaded\Z/

      options[:min_bytes] = 1.bytes
      options[:max_wait_time] = 0.2.seconds
      options[:max_bytes_per_partition] = 10.kilobytes
      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false

      sig { params(kwargs: T.untyped).void }
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

        self.dead_letter_topic = "package_registry.v0.PackageVersionDownloaded.DeadLetter"
      end

      sig { params(message: GitHub::StreamProcessors::Message).void }
      def process_message(message)
        if GitHub.billing_enabled?
          create_data_transfer_line_item(message)
        end
      end

      sig { params(message: GitHub::StreamProcessors::Message).void }
      def create_data_transfer_line_item(message)
        registry_type = message.value.dig(:package, :registry_type)
        if registry_type == :DOCKER
          return message.skip("docker")
        end

        if is_retrial_for_migration_sync?(message)
          return message.skip("retry for migration sync")
        end

        owner = with_read { User.find_by(id: owner_id(message)) }
        if owner.nil?
          return message.skip("missing_owner")
        end

        if public_repository?(message)
          return message.skip("public_repository")
        end

        if download_originated_from_actions?(message)
          return message.skip("downloaded_from_actions")
        end

        billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(owner)
        billable_owner = billable_owner_designator.billable_owner
        if billable_owner.skip_metered_billing_permission_check_for?(product: :packages)
          return message.skip("metered_permissions_skipped")
        end

        GitHub.logger.info(
          "Billing Message Received",
          "code.namespace" => self.class.name,
          "code.function" => "#create_data_transfer_line_item",
          "gh.registry.message.type" => "package_version_downloaded",
          "gh.registry.message.actor.type" => message.value.dig(:actor, :type),
          "gh.registry.message.actor_id" => message.value.dig(:actor, :id),
          "gh.registry.message.owner_id" => message.value.dig(:package, :owner_id),
          "gh.registry.message.package_id" => message.value.dig(:package, :id),
        )

        # We must not pass the actor_id if it's not a user.
        # Reporting uses the actor_id to determine the user who performed the action.
        # Passing it in case of an installation will result in random user names showing up in the report.
        # Codespaces can pull packages during pre-builds, which are not associated with a user.
        # A user using Codespaces is also using the same token type. It might be possible to identify the `user_id` in this case.
        # However, we haven't found a way to do so yet. For now, we are not associating any Codespace requests with users.
        actor_id = if message.value.dig(:actor, :type) == :USER
          message.value.dig(:actor, :id)
        else
          nil
        end

        if billable_owner.customer&.packages_billed_on_billing_platform?
          size_in_gib = message.value.dig(:file, :size).fdiv(1.gigabyte)
          event_id = message.value[:event_id]
          customer_id = customer_id(owner)

          usage = {
            sku: "packages_bandwidth",
            quantity: size_in_gib,
            usage_at: downloaded_at(message),
            source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/event_id/#{event_id}",
            usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, event_id), # rubocop:disable GitHub/InsecureHashAlgorithm
            entity: {
              customer_id: customer_id,
              actor_id: actor_id,
            }
          }

          result = Hydro::PublishRetrier.publish(usage, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

          if result.error
            GitHub.logger.error("Failed to publish vNext billing event",
              "code.namespace" => self.class.name,
              "code.function" => "#create_data_transfer_line_item",
              "gh.registry.message.type" => "package_version_downloaded",
              "gh.registry.message.actor.type" => message.value.dig(:actor, :type),
              "gh.registry.message.actor_id" => message.value.dig(:actor, :id),
              "gh.registry.message.owner_id" => message.value.dig(:package, :owner_id),
              "gh.registry.message.package_id" => message.value.dig(:package, :id),
            )
          end
        else
          ::Billing::PackageRegistry::DataTransferLineItemCreator.create(
              owner: owner,
              actor_id: actor_id,
              registry_package_id: package_id(message),
              registry_package_version_id: version_id(message),
              name: message.value.dig(:package, :name),
              size_in_bytes: message.value.dig(:file, :size),
              download_id: message.value[:event_id],
              downloaded_at: downloaded_at(message),
              source_uri: "gid://git-hub/StreamProcessor/#{DEFAULT_GROUP_ID}/event_id/#{message.value[:event_id]}"
          )
        end
      end

      sig { params(message: GitHub::StreamProcessors::Message).returns(Integer) }
      def owner_id(message)
        message.value.dig(:package, :owner_id)
      end

      sig { params(message: GitHub::StreamProcessors::Message).returns(Integer) }
      def package_id(message)
        message.value.dig(:package, :id)
      end

      sig { params(message: GitHub::StreamProcessors::Message).returns(Integer) }
      def version_id(message)
        message.value.dig(:version, :id)
      end

      sig { params(owner: User).returns(T.nilable(Integer)) }
      def customer_id(owner)
        if owner.delegate_billing_to_business?
          owner.business.customer_id
        else
          owner.customer&.id
        end
      end

      sig { params(message: GitHub::StreamProcessors::Message).returns(Time) }
      def downloaded_at(message)
        message_seconds = message.value.dig(:downloaded_at, :seconds)
        if message_seconds.present?
          Time.at(message_seconds)
        else
          Time.now.utc
        end
      end

      sig { params(message: GitHub::StreamProcessors::Message).returns(T::Boolean) }
      def public_repository?(message)
        repository_visibility(message) == "public"
      end

      sig { params(message: GitHub::StreamProcessors::Message).returns(T::Boolean) }
      def download_originated_from_actions?(message)
        downloaded_from(message) == "actions"
      end

      sig { params(message: GitHub::StreamProcessors::Message).returns(T::Boolean) }
      def is_retrial_for_migration_sync?(message)
        retry_count = message.value.dig(:retry_count)
        retry_count.present? && retry_count > 0
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

      sig { params(message: GitHub::StreamProcessors::Message).returns(String) }
      def downloaded_from(message)
        if message.value[:via_actions] == "false" || message.value[:via_actions] == false
          "unknown"
        else
          "actions"
        end
      end

      private

      sig do
        params(message: GitHub::StreamProcessors::Message).returns(T::Hash[T.any(String, Symbol), T.untyped])
      end
      def error_context_for_message(message)
        super(message).merge({
          user_id: owner_id(message),
          package_id: message.value.dig(:package, :id),
        })
      end
    end
  end
end
