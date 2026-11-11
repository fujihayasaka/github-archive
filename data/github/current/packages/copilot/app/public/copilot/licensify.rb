# typed: strict
# frozen_string_literal: true

module Copilot
  module Licensify
    extend T::Helpers
    include ::Licensing::Licensify

    class << self
      # Event payload we emit to GlobalInstrumenter / Hydro subscription.
      CopilotLicensifyEventPayload = T.type_alias do
        {
          assignable_entity_id: Integer,
          assignable_entity_type: String,
          customer_id: T.nilable(Integer),
          actor: T.nilable(::User),
          is_enabled: T::Boolean,
          effective_at: T.any(Time, ActiveSupport::TimeWithZone),
          product_sku_name: String,
          pending_cancellation_date: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
          plan_name: T.nilable(String),
          plan_owner_type: T.nilable(String),
          plan_owner_id: T.nilable(Integer),
          trial_plan: T.nilable(String),
          trial_end_date: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
        }
      end

      sig { params(seat_assignment: Copilot::SeatAssignment, actor: T.nilable(::User)).void }
      def emit_enable_event(seat_assignment, actor:)
        return unless seat_assignment.assignable.present?
        message = build_licensify_event_payload(seat_assignment, actor, true)
        emit_license_enablement_toggled_event(message)
      end

      sig { params(seat_assignment: Copilot::SeatAssignment, actor: T.nilable(::User)).void }
      def emit_disable_event(seat_assignment, actor:)
        return unless seat_assignment.assignable.present?
        message = build_licensify_event_payload(seat_assignment, actor, false)
        emit_license_enablement_toggled_event(message)
      end

      sig { params(seat_assignment: Copilot::SeatAssignment, actor: T.nilable(::User)).void }
      def emit_unassign_event(seat_assignment, actor:)
        emit_disable_event(seat_assignment, actor: actor)
      end

      sig { params(seat_assignment: Copilot::SeatAssignment, actor: T.nilable(::User)).void }
      def emit_reinstate_event(seat_assignment, actor:)
        emit_enable_event(seat_assignment, actor: actor)
      end

      private

      sig do
        params(
          seat_assignment: Copilot::SeatAssignment,
          actor: T.nilable(::User),
          enabled: T::Boolean,
          effective_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
        ).returns(CopilotLicensifyEventPayload)
      end
      def build_licensify_event_payload(seat_assignment, actor, enabled, effective_at = nil)
        owner = seat_assignment.owner
        copilot_owner = copilot_owner_for(owner)

        {
          assignable_entity_id: seat_assignment.assignable_id,
          assignable_entity_type: seat_assignment.assignable_type,
          customer_id: copilot_owner&.customer_for&.id,
          actor: actor,
          is_enabled: enabled,
          effective_at: effective_at || Time.current,
          product_sku_name: get_product_sku_name(copilot_owner),
          pending_cancellation_date: seat_assignment.pending_cancellation_date&.to_time&.utc,
          plan_name: copilot_owner&.copilot_plan,
          plan_owner_type: get_plan_owner_type(copilot_owner),
          plan_owner_id: copilot_owner&.id,
          trial_plan: get_trial_plan(copilot_owner),
          trial_end_date: get_trial_end_date(copilot_owner),
        }
      end

      sig { params(copilot_owner: T.nilable(T.any(::Copilot::Business, ::Copilot::Organization))).returns(String) }
      def get_product_sku_name(copilot_owner)
        return "copilot_for_business" unless copilot_owner

        if copilot_owner.copilot_plan_enterprise?
          # If the user has already purchased CE, make sure that any active CE trials are still charged with the CB SKU
          return "copilot_for_business" if copilot_owner.on_free_copilot_enterprise_trial?

          "copilot_enterprise"
        elsif copilot_owner.copilot_standalone?
          "copilot_standalone"
        else
          "copilot_for_business"
        end
      end

      sig { params(copilot_owner: T.nilable(T.any(::Copilot::Business, ::Copilot::Organization))).returns(T.nilable(String)) }
      def get_plan_owner_type(copilot_owner)
        case copilot_owner
        when ::Copilot::Organization
          "Organization"
        when ::Copilot::Business
          "Business"
        end
      end

      sig do
        params(
          copilot_owner: T.nilable(T.any(::Copilot::Business, ::Copilot::Organization))
        ).returns(T.nilable(String))
      end
      def get_trial_plan(copilot_owner)
        return nil unless copilot_owner.is_a?(::Copilot::Organization) && copilot_owner.on_free_trial?

        copilot_owner.business_trial&.copilot_plan
      end

      sig do
        params(
          copilot_owner: T.nilable(T.any(::Copilot::Business, ::Copilot::Organization))
        ).returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone)))
      end
      def get_trial_end_date(copilot_owner)
        return nil unless copilot_owner.is_a?(::Copilot::Organization) && copilot_owner.on_free_trial?

        trial_end = copilot_owner.business_trial&.ends_at
        return nil unless trial_end
        return nil if trial_end.to_date == Copilot::BusinessTrial::INACTIVE_DATE

        trial_end.utc
      end

      sig { params(owner: T.nilable(T.any(::Business, ::Organization))).returns(T.nilable(T.any(::Copilot::Business, ::Copilot::Organization))) }
      def copilot_owner_for(owner)
        return nil unless owner

        case owner
        when ::Business
          Copilot::Business.new(owner)
        when ::Organization
          Copilot::Organization.new(owner)
        end
      end

      sig { params(message: CopilotLicensifyEventPayload).void }
      def emit_license_enablement_toggled_event(message)
        if message[:customer_id].nil?
          Copilot::Instrumentation::EventSubscriber.log_missing(
            missing: [:customer_id],
            payload: message,
            event_name: ::Copilot::Events::COPILOT_LICENSE_ENABLEMENT_TOGGLED,
          )
          return
        end

        GlobalInstrumenter.instrument(::Copilot::Events::COPILOT_LICENSE_ENABLEMENT_TOGGLED, message)
      end
    end
  end
end
