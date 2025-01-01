# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class PackageVersionDeletedProcessor < BaseProcessor

        default_to_write_connection!

        include TransientErrorResiliency

        self.slack_pause_notifications_channel = "#billing-alerts"

        DEFAULT_GROUP_ID = "package_version_deleted_processor"
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageVersionDeleted\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 100.kilobytes
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        # Initialize the PackageVersionDeletedProcessor
        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.dead_letter_topic = "package_registry.v0.PackageVersionDeleted.DeadLetter"
        end

        # Create a Billing::SharedStorage::ArtifactEvent for the message
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
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

          size_in_bytes = message.value.dig(:version, :package_size)
          if size_in_bytes.to_i.zero?
            return message.skip("zero_size")
          end

          registry_type = message.value.dig(:package, :registry_type)
          if [:NPM, :NUGET, :RUBYGEMS].include?(registry_type.to_sym)
            ms = ActiveRecord::Base.connected_to(role: :reading) do
              Registry::PackageVersion.where(id: message.value.dig(:version, :id)).pluck(:migration_state).first
            end
            return message.skip("migrated_version") if ms == "complete"
          end

          ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry(max_retry_count: 5) do
            safe_trigger_heartbeat
            ::Billing::SharedStorage::ArtifactEvent.create!(
              owner_id: message.value.dig(:package, :owner_id).to_i,
              repository_id: message.value.dig(:package, :repository, :id),
              effective_at: Time.at(message.value.dig(:deleted_at, :seconds)),
              source: :gpr,
              repository_visibility: repository_visibility(message),
              event_type: :remove,
              size_in_bytes: size_in_bytes,
              source_artifact_id: message.value.dig(:version, :id),
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
