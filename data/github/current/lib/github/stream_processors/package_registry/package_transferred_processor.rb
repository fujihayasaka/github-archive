# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class PackageTransferredProcessor < BaseProcessor
        extend T::Sig

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
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
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
