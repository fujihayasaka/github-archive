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
          pending_cancellation_date: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
          plan_name: T.nilable(String),
          plan_owner_type: T.nilable(String),
          plan_owner_id: T.nilable(Integer),
          trial_plan: T.nilable(String),
          trial_end_date: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
          business_team_ids: T.nilable(T::Array[Integer]),
          is_disable_seat_management_enablement: T::Boolean,
        }
      end

      sig { params(seat_assignment: Copilot::SeatAssignment, actor: T.nilable(::User)).void }
      def emit_enable_event(seat_assignment, actor:)
        unless seat_assignment.assignable.present?
          GitHub.logger.info(
            "Skipping Licensify enable event emission because assignable is missing",
            "gh.copilot.seat_assignment.id" => seat_assignment.id,
            "gh.copilot.seat_assignment.assignable.id" => seat_assignment.assignable_id,
            "gh.copilot.seat_assignment.assignable.type" => seat_assignment.assignable_type,
            "gh.copilot.owner.id" => seat_assignment.owner_id,
            "gh.copilot.owner.type" => seat_assignment.owner_type
          )
          return
        end

        message = build_licensify_event_payload(
          seat_assignment,
          actor,
          true,
          nil,
          seat_assignment.licensify_enable_event_is_disable_seat_management_enablement || false
        )
        emit_license_enablement_toggled_event(message)
      end

      # should be called due to pending cancellation
      #
      # downstream licensify event consumers will interpret this as an unassignment, keeping the product enablement
      # while updating the pending cancellation date to denote when the license will be fully revoked
      sig { params(seat_assignment: Copilot::SeatAssignment, actor: T.nilable(::User)).void }
      def emit_unassign_event(seat_assignment, actor:)
        unless seat_assignment.assignable.present?
          GitHub.logger.info(
            "Skipping Licensify unassign event emission because assignable is missing",
            "gh.copilot.seat_assignment.id" => seat_assignment.id,
            "gh.copilot.seat_assignment.assignable.id" => seat_assignment.assignable_id,
            "gh.copilot.seat_assignment.assignable.type" => seat_assignment.assignable_type,
            "gh.copilot.owner.id" => seat_assignment.owner_id,
            "gh.copilot.owner.type" => seat_assignment.owner_type
          )
          return
        end

        message = build_licensify_event_payload(seat_assignment, actor, true)
        emit_license_enablement_toggled_event(message)
      end

      # should be called when a seat assignment is destroyed
      #
      # downstream licensify event consumers will interpret this as a full disablement of the product,
      # and delete the product enablement
      sig { params(seat_assignment: Copilot::SeatAssignment, actor: T.nilable(::User)).void }
      def emit_disable_event(seat_assignment, actor:)
        unless seat_assignment.assignable.present?
          GitHub.logger.info(
            "Skipping Licensify disable event emission because assignable is missing",
            "gh.copilot.seat_assignment.id" => seat_assignment.id,
            "gh.copilot.seat_assignment.assignable.id" => seat_assignment.assignable_id,
            "gh.copilot.seat_assignment.assignable.type" => seat_assignment.assignable_type,
            "gh.copilot.owner.id" => seat_assignment.owner_id,
            "gh.copilot.owner.type" => seat_assignment.owner_type
          )
          return
        end

        message = build_licensify_event_payload(seat_assignment, actor, false)
        emit_license_enablement_toggled_event(message)
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
          is_disable_seat_management_enablement: T::Boolean,
        ).returns(CopilotLicensifyEventPayload)
      end
      def build_licensify_event_payload(seat_assignment, actor, enabled, effective_at = nil, is_disable_seat_management_enablement = false)
        owner = seat_assignment.owner
        copilot_owner = copilot_owner_for(owner)

        {
          assignable_entity_id: seat_assignment.assignable_id,
          assignable_entity_type: seat_assignment.assignable_type,
          customer_id: copilot_owner&.customer_for&.id,
          actor: actor,
          is_enabled: enabled, # true when the seat assignment exists (even pending cancellation), false when destroyed
          effective_at: effective_at || Time.current,
          pending_cancellation_date: seat_assignment.pending_cancellation_date&.to_time&.utc,
          plan_name: copilot_owner&.copilot_plan,
          plan_owner_type: get_plan_owner_type(copilot_owner),
          plan_owner_id: copilot_owner&.id,
          trial_plan: get_trial_plan(copilot_owner),
          trial_end_date: get_trial_end_date(copilot_owner),
          business_team_ids: get_business_team_ids(seat_assignment),
          is_disable_seat_management_enablement: is_disable_seat_management_enablement,
        }
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
        case copilot_owner
        when ::Copilot::Business
          return nil unless copilot_owner.business_object.trial?

          # Trials at the Business level always have the Copilot Business trial plan
          "business"
        when ::Copilot::Organization
          return nil unless copilot_owner.on_free_trial?

          copilot_owner.business_trial&.copilot_plan
        end
      end

      sig do
        params(
          copilot_owner: T.nilable(T.any(::Copilot::Business, ::Copilot::Organization))
        ).returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone)))
      end
      def get_trial_end_date(copilot_owner)
        case copilot_owner
        when ::Copilot::Business
          return nil unless copilot_owner.business_object.trial?

          copilot_owner.business_object.trial_expires_at&.utc
        when ::Copilot::Organization
          return nil unless copilot_owner.on_free_trial?

          trial_end = copilot_owner.business_trial&.ends_at
          return nil unless trial_end
          return nil if trial_end.to_date == Copilot::BusinessTrial::INACTIVE_DATE

          trial_end.utc
        end
      end

      # Returns the IDs of Business Teams that are assigned to the organization
      # when the seat assignment is for an Organization. This includes:
      # - Business Teams with organization_selection_type = :selected that are explicitly assigned to the org
      # - Business Teams with organization_selection_type = :all that belong to the same business as the org
      #
      # Returns nil for non-Organization seat assignments.
      sig { params(seat_assignment: Copilot::SeatAssignment).returns(T.nilable(T::Array[Integer])) }
      def get_business_team_ids(seat_assignment)
        return nil unless seat_assignment.assignable_type == "Organization"

        organization = seat_assignment.assignable
        return nil unless organization.is_a?(::Organization)

        business = organization.business
        return [] unless business.present?

        # Get Business Teams explicitly assigned to this organization (selected type)
        selected_team_ids = ::BusinessTeamOrgAssignment
          .where(organization_id: organization.id)
          .pluck(:team_id)

        # Get Business Teams assigned to all orgs in the business (all type)
        all_orgs_team_ids = ::BusinessTeam
          .where(business_id: business.id, organization_selection_type: :all)
          .pluck(:id)

        (selected_team_ids + all_orgs_team_ids).uniq
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
