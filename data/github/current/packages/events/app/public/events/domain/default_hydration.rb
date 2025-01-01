# typed: strict
# frozen_string_literal: true

module Events
  class Domain
    # DefaultHydration provides a shared, simplified hydration method for events v2
    class DefaultHydration
      # Public: Default hydration method for events v2 webhook payload generation
      #
      # event_class - The Hook::Event class to hydrate (e.g., Hook::Event::IssuesEvent)
      # attributes_class - The hook attributes class to use
      # req - The Twirp request as a EventsPlatform::V1::HydrateRequest
      #
      # Returns the Twirp response as a Hash with results and has_target_repository_disabled_webhooks or a Twirp::Error
      sig { params(event_class: T.class_of(Hook::Event), attributes_class: T.untyped, req: EventsPlatform::V1::HydrateRequest).returns(T.any({ results: T::Array[T.untyped], has_target_repository_disabled_webhooks: T.nilable(T::Boolean) }, Twirp::Error)) }
      def self.hydrate(event_class:, attributes_class:, req:) # rubocop:disable Metrics/MethodLength
        # Basic validation
        missing_args = []
        missing_args << "tier1_event" if req.tier1_event.blank?
        missing_args << "payload_versions" if req.payload_versions.blank?
        return Twirp::Error.invalid_argument("Missing required fields: #{missing_args.join(', ')}", argument: missing_args.join(", ")) unless missing_args.empty?
        tier1_event = T.must(req.tier1_event)

        requested_versions = req.payload_versions

        # Check replication status
        event_type = tier1_event.type
        event_type_sym = event_type.is_a?(Integer) ? Hydro::Schemas::EventsPlatform::V0::Entities::EventType.lookup(event_type) : event_type
        return Twirp::Error.invalid_argument("invalid event type") if event_type_sym.nil?
        replication_data = Events::Domain.domain.replication_data(tier1_event.metadata&.tracked_writes, event_type_sym)
        return Twirp::Error.failed_precondition("replication incomplete") unless replication_data.exceeded_maximum_timeout? || replication_data.replications_completed?

        begin
          event_attributes = attributes_class.decode(tier1_event.hook_event_attributes&.message).to_h
        rescue StandardError => e
          return Twirp::Error.internal("failed to decode event attributes", message: e.message)
        end

        if tier1_event.event_attachment&.message
          event_attributes[:attachment_data] = T.must(tier1_event.event_attachment).message
        end

        event = event_class.new(event_attributes)

        # Event hydrator should not retry and should deliver a Tier 2 event with
        # RESULT_CODE_RESOURCE_NOT_FOUND
        return Twirp::Error.not_found("event is not deliverable") unless event.deliverable?

        # Perform hydration for each requested version
        hydrated_events = requested_versions.map do |version|
          unless is_valid?(version)
            next {
              version: version,
              code: :RESULT_CODE_INVALID_VERSION
            }
          end
          payload = event.to_payload_hash(version: selected_version(version))
          {
            version: version,
            payload: payload.to_json,
            code: :RESULT_CODE_SUCCESS
          }
        end

        target_repository = event.target_repository
        target_repository_disabled_webhooks = target_repository.present? && Events::Domain.domain.has_target_repository_disabled_webhooks(target_repository)

        { results: hydrated_events, has_target_repository_disabled_webhooks: target_repository_disabled_webhooks }
      rescue ActiveRecord::RecordNotFound => e
        handle_record_not_found_error(e)
      end

      sig { params(version: String).returns(T::Boolean) }
      private_class_method def self.is_valid?(version)
        Api::Versioning.usable_version?(version)
      end

      sig { params(version: String).returns(T.nilable(Api::SelectedVersion)) }
      private_class_method def self.selected_version(version)
        # We use Api::SelectedVersion::REASON_PINNED here because it was decided that only valid payload versions will
        # be accepted by this endpoint. We will not set a default version as a graceful fallback if the version requested
        # is invalid. The appropriate reason to use therefore is Api::SelectedVersion::REASON_PINNED
        Api::SelectedVersion.new(version, version, Api::SelectedVersion::REASON_PINNED)
      end

      sig { params(record_not_found_error: ActiveRecord::RecordNotFound).returns(Twirp::Error) }
      private_class_method def self.handle_record_not_found_error(record_not_found_error)
        # Cases where records are not found by ID are explicitly retried in events V1 by the HookDeliveryRaceConditionCheckJob.
        # This logic exists to replicate that scenario, so that we don't drop events in this scenario in Events V2.
        # We want the Twirp endpoints to return a 404 if the primary resource is not found so that the hydration can be retried,
        # but in the case of some other type of ActiveRecord::RecordNotFound error, we want to re-raise and treat it as an unexpected failure.
        model_name, id = if /\ACouldn't find ([\w:]+) with '?ID'?=(\d+)\z/i =~ record_not_found_error.message
          [$1, $2.to_i]
        end

        return internal_error(record_not_found_error) unless model_name && id

        Twirp::Error.not_found("Primary resource not found by ID and should be retried: #{model_name} with ID #{id}", retry: "true")
      end

      sig { params(e: StandardError).returns(Twirp::Error) }
      private_class_method def self.internal_error(e)
        err = Twirp::Error.internal("Failed to hydrate payload.", message: e.message)
      end
    end
  end
end
