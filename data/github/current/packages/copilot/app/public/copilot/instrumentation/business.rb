# typed: strict
# frozen_string_literal: true

module Copilot
  module Instrumentation
    module Business
      include Helpers

      sig do
        params(telemetry_snapshot: Copilot::TelemetrySnapshot).void
      end
      def instrument_telemetry_snapshot(telemetry_snapshot)
        return unless telemetry_snapshot.telemetry_snapshot_id # we need this to be present because it signifies that the user has access

        send_to_hydro(
          ::Copilot::Events::TELEMETRY_SNAPSHOT,
          {
            telemetry_snapshot: telemetry_snapshot,
          },
        )
      end

      sig { params(organization: ::Organization, blocking_reason: String, integration_id: T.nilable(String)).void }
      def instrument_organization_abuse_event(organization, blocking_reason, integration_id = nil)
        send_to_hydro(::Copilot::Events::ORGANIZATION_ABUSE_EVENT, {
          organization: organization,
          integration_id: integration_id,
          blocking_reason: blocking_reason,
        })
      end

      # This is when the enterprise admin saves their settings and agree to the clckwrap
      sig { params(actor: ::User, business: ::Business, terms_type: T.nilable(String)).void }
      def instrument_clickwrap_saved(actor, business, terms_type = "product")
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_CLICKWRAP_SAVED, {
          actor: actor,
          business: business,
          terms_type: terms_type
        })
      end

      # This is when the enterprise admin is shown the clickwrap
      sig { params(actor: ::User, business: ::Business).void }
      def instrument_clickwrap_shown(actor, business)
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_CLICKWRAP_SHOWN, {
          actor: actor,
          business: business,
        })
      end

      # This is when the enterprise admin changes their copilot settings in the setting controller
      sig do
        params(
          actor: ::User,
          business: ::Business,
          old_settings: T::Hash[Symbol, Symbol],
          new_settings: T::Hash[Symbol, Symbol],
        ).void
      end
      def instrument_enterprise_settings_changed(actor, business, old_settings: {}, new_settings: {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_ENTERPRISE_SETTINGS_CHANGED, {
          actor: actor,
          business: business,
          old_settings: old_settings,
          new_settings: new_settings,
        })
      end

      sig do
        params(
          user: ::User,
          subscription_item: ::Billing::Public::SubscriptionItem,
          seat: Copilot::Seat,
          details: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_individual_seat_converted(user, subscription_item, seat, details = {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_INDIVIDUAL_SEAT_CONVERTED, {
          user: user,
          subscription_item_id: subscription_item.id,
          subscription_item_duration: subscription_item.interval.to_s,
          seat: seat,
          details: details,
        })
      end

      # This is when the org admin changes their copilot settings in the setting controller
      sig do
        params(
          organization: ::Organization,
          actor: ::User,
          old_settings: T::Hash[Symbol, Symbol],
          new_settings: T::Hash[Symbol, Symbol],
        ).void
      end
      def instrument_organization_settings_changed(organization, actor, old_settings: {}, new_settings: {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_ORG_SETTINGS_CHANGED, {
          organization: organization,
          actor: actor,
          old_settings: old_settings,
          new_settings: new_settings,
        })
      end

      sig do
        params(
          owner: T.any(::Business, ::Organization),
          user_id: Integer,
          actor: T.nilable(::User),
          event_type: Symbol,
          details: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_seat_added(owner, user_id, actor, event_type, details = {})
        user = ::User.find_by(id: user_id)
        # there should really only be one seat for a user and owner. should is doing a lot of work here
        seat = Copilot::Seat.for_assigned_user_and_owner(user_id, owner).first

        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ADDED, {
          owner: owner,
          seat: seat,
          user: user,
          actor: actor,
          event_type: event_type,
          details: details,
        })
      end

      sig do
        params(
          seat_assignment: Copilot::SeatAssignment,
          existing_seats_count: Integer,
          matched_existing_seat_count: Integer,
          seat_to_insert_count: Integer,
        ).void
      end
      def instrument_copilot_for_business_assignment_conversion(seat_assignment, existing_seats_count, matched_existing_seat_count, seat_to_insert_count)
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_CONVERSION, {
          seat_assignment: seat_assignment,
          owner: seat_assignment.owner,
          existing_seats_count: existing_seats_count,
          matched_existing_seat_count: matched_existing_seat_count,
          seat_to_insert_count: seat_to_insert_count,
        })
      end

      sig do
        params(
          seat_assignment: Copilot::SeatAssignment,
          actor: T.nilable(::User),
          event_type: Symbol,
          details: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_seat_assignment_created(seat_assignment, actor, event_type, details = {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_CREATED, {
          assignment: seat_assignment,
          owner: seat_assignment.owner,
          actor: actor,
          event_type: event_type,
          details: details,
        })
      end

      sig do
        params(
          seat_assignment: Copilot::SeatAssignment,
          actor: T.nilable(::User),
          details: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_seat_assignment_refreshed(seat_assignment, actor, details = {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_REFRESHED, {
          assignment: seat_assignment,
          owner: seat_assignment.owner,
          event_type: :refresh,
          actor: actor,
          details: details,
        })
      end

      sig do
        params(
          seat_assignment: Copilot::SeatAssignment,
          actor: T.nilable(::User),
          details: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_seat_assignment_reused(seat_assignment, actor, details = {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_REUSED, {
          assignment: seat_assignment,
          owner: seat_assignment.owner,
          event_type: :reuse,
          actor: actor,
          details: details,
        })
      end

      sig do
        params(
          seat_assignment: Copilot::SeatAssignment,
          actor: T.nilable(::User),
          event_type: Symbol,
          details: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_seat_assignment_unassigned(seat_assignment, actor, event_type, details = {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_UNASSIGNED, {
          assignment: seat_assignment,
          owner: seat_assignment.owner,
          event_type: event_type,
          actor: actor,
          details: details,
        })
      end

      sig do
        params(
          seat: Copilot::Seat,
          actor: T.nilable(::User),
          staff_cancelled: T::Boolean,
          event_type: T.nilable(Symbol),
          details: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_seat_cancelled(seat, actor, staff_cancelled = false, event_type = nil, details = {})
        if staff_cancelled
          instrument(
            ::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED_BY_STAFF,
            {
              user: seat.assigned_user,
              owner: seat.seat_assignment&.owner,
              seat: seat,
              actor: actor,
              event_type: event_type,
              details: details,
            },
            true
          )
        else
          instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED, {
            user: seat.assigned_user,
            owner: seat.seat_assignment&.owner,
            seat: seat,
            actor: actor,
            event_type: event_type,
            details: details,
          })
        end
      end

      sig do
        params(
          owner: T.any(::Business, ::Organization),
          seat_emission: Copilot::SeatEmission,
          already_billed_user_ids_count: T.nilable(Integer),
          number_of_days_in_billing_cycle: T.nilable(Float),
          per_seat_rate: T.nilable(Float),
          seat_count: T.nilable(Float),
        ).void
      end
      def instrument_copilot_for_business_seat_emission(
        owner,
        seat_emission,
        already_billed_user_ids_count: nil,
        number_of_days_in_billing_cycle: nil,
        per_seat_rate: nil,
        seat_count: nil
      )
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_EMISSION, {
          owner: owner,
          seat_emission: seat_emission,
          already_billed_user_ids_count: already_billed_user_ids_count,
          number_of_days_in_billing_cycle: number_of_days_in_billing_cycle,
          per_seat_rate: per_seat_rate,
          seat_count: seat_count,
        })
      end

      sig do
        params(
          owner: T.any(::Business, ::Organization),
          reason: String,
        ).void
      end
      def instrument_copilot_for_business_seat_emission_skipped(
        owner,
        reason
      )
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_EMISSION_SKIPPED, {
          owner: owner,
          reason: reason,
        })
      end

      sig do
        params(
          owner: T.any(::Business, ::Organization),
          sku: String,
        ).void
      end
      def instrument_copilot_seat_emission_on_billing_platform(
        owner,
        sku
      )
        instrument(::Copilot::Events::COPILOT_SEAT_EMISSION_ON_BILLING_PLATFORM, {
          owner: owner,
          sku: sku,
        })
      end

      sig do
        params(
          actor: T.nilable(::User),
          organization: ::Organization,
          old_value: String,
          new_value: String,
          details: T::Hash[T.any(Symbol, String), T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_seat_management_changed(actor, organization, old_value, new_value, details = {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_MANAGEMENT_CHANGED, {
          actor: actor,
          organization: organization,
          old_value: old_value,
          new_value: new_value,
          details: details,
        })
      end

      sig do
        params(
          seat: Copilot::Seat,
          staff_actor: T.nilable(::User),
          details: T::Hash[T.any(Symbol, String), T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def instrument_copilot_for_business_seat_uncancelled(seat, staff_actor, details = {})
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_UNCANCELLED_BY_STAFF, {
          seat: seat,
          staff_actor: staff_actor,
          details: details,
        })
      end

      sig do
        params(
          staff_actor: ::User,
          organization: ::Organization,
          seat_count: Integer,
          trial_duration_days: Integer,
          copilot_plan: String,
        ).void
      end
      def instrument_copilot_business_trial_created(staff_actor, organization, seat_count, trial_duration_days, copilot_plan)
        business = organization.business

        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_CREATED, {
          business: business,
          copilot_plan: copilot_plan,
          organization: organization,
          seat_count: seat_count,
          staff_actor: staff_actor,
          trial_duration_days: trial_duration_days,
        })
      end

      # this is called when the business trial expires - NOT WHEN UPGRADED
      sig do
        params(
          organization: ::Organization,
        ).void
      end
      def instrument_copilot_business_trial_ended(organization)
        business = organization.business
        copilot_org = Copilot::Organization.new(organization)
        trial = copilot_org.business_trial

        return unless trial.present?

        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_ENDED, {
          business: business,
          copilot_plan: trial.copilot_plan,
          organization: organization,
          seat_count: 0, # trial.seat_count will be deprecated
          trial_duration_days: trial.trial_length,
          trial_ended_at: trial.ends_at,
          trial_started_at: trial.started_at,
        })
      end

      sig do
        params(
          org_admin: ::User,
          business_trial: ::Copilot::BusinessTrial,
        ).void
      end
      def instrument_copilot_business_trial_started(org_admin, business_trial)
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_STARTED, {
          copilot_plan: business_trial.copilot_plan,
          org_admin: org_admin,
          organization: business_trial.trialable,
          trial: business_trial,
        })
      end

      sig do
        params(
          staff_actor: ::User,
          business_trial: ::Copilot::BusinessTrial,
        ).void
      end
      def instrument_copilot_business_trial_upgraded(staff_actor, business_trial)
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_UPGRADED, {
          copilot_plan: business_trial.copilot_plan,
          organization: business_trial.trialable,
          staff_actor: staff_actor,
          trial: business_trial,
        })
      end

      sig do
        params(
          staff_actor: ::User,
          business_trial: ::Copilot::BusinessTrial,
          seat_count: Integer,
          trial_duration_days: Integer,
        ).void
      end
      def instrument_copilot_business_trial_extended(staff_actor, business_trial, seat_count, trial_duration_days)
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_EXTENDED, {
          copilot_plan: business_trial.copilot_plan,
          organization: business_trial.trialable,
          seat_count: seat_count,
          staff_actor: staff_actor,
          trial_duration_days: trial_duration_days,
          trial: business_trial,
        })
      end

      sig do
        params(
          staff_actor: ::User,
          business_trial: ::Copilot::BusinessTrial,
          reason: String,
          previous_ends_at: ActiveSupport::TimeWithZone,
          old_copilot_plan: String,
        ).void
      end
      def instrument_copilot_business_trial_changed(staff_actor, business_trial, reason, previous_ends_at, old_copilot_plan)
        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_TRIAL_CHANGED, {
          new_copilot_plan: business_trial.copilot_plan,
          old_copilot_plan: old_copilot_plan,
          organization: business_trial.trialable,
          previous_trial_ends_at: previous_ends_at,
          reason: reason,
          staff_actor: staff_actor,
          trial: business_trial,
          updated_trial_ends_at: business_trial.ends_at,
        })
      end

      sig do
        params(
          owner: T.any(::Repository, ::Organization, ::Business),
          actor: T.nilable(::User),
          document: String,
        ).void
      end
      def instrument_content_exclusion_changed(owner, actor, document)
        payload = { actor:, excluded_paths: document, owner_type: owner.class.name }
        if owner.is_a?(::Organization)
          payload.merge!(organization: owner)
        elsif owner.is_a?(::Business)
          payload.merge!(business: owner)
        else
          payload.merge!(repository: owner)
          payload.merge!(organization: owner.owner) if owner.owner.is_a?(::Organization)
        end

        instrument(::Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED, payload)
      end

      sig do
        params(
          actor: T.nilable(::User),
          owner: T.any(::Business, ::Organization),
          old_plan: String,
          plan: String,
        ).void
      end
      def instrument_copilot_plan_changed(actor, owner, old_plan, plan)
        instrument(::Copilot::Events::COPILOT_PLAN_CHANGED, {
          actor: actor,
          owner: owner,
          old_plan: old_plan,
          plan: plan,
        })
      end

      sig do
        params(
          actor: T.nilable(::User),
          owner: T.any(::Business, ::Organization),
          current_plan: String,
          scheduled_plan: String,
        ).void
      end
      def instrument_copilot_plan_downgrade_scheduled(actor, owner, current_plan, scheduled_plan)
        instrument(::Copilot::Events::COPILOT_PLAN_DOWNGRADE_SCHEDULED, {
          actor: actor,
          owner: owner,
          current_plan: current_plan,
          scheduled_plan: scheduled_plan,
        })
      end

      sig { params(target: T.any(::Business, ::Organization), reason: String).void }
      def instrument_copilot_access_revoked(target, reason)
        payload = { reason: reason }

        if target.is_a?(::Business)
          copilot_biz = Copilot::Business.new(target)
          payload.merge!({ owner: target, plan: copilot_biz.copilot_plan })
        else
          copilot_org = Copilot::Organization.new(target)
          payload.merge!({ owner: target, plan: copilot_org.copilot_plan })
        end

        instrument(::Copilot::Events::COPILOT_ACCESS_REVOKED, payload)
      end

      sig { params(actor: ::User, owner: ::Organization, kb: Orgs::CopilotSettings::ChatSettingsController::KbCreationPayload).void }
      def instrument_knowledge_base_created(actor, owner, kb)
        instrument(::Copilot::Events::KNOWLEDGE_BASE_CREATED, {
          actor: actor,
          organization: owner,
          organization_id: owner.id,
          knowledge_base_id: kb[:id],
          knowledge_base_name: kb[:name],
          knowledge_base_description: kb[:description],
          number_of_repos: kb[:repos].count,
        })
      end

      sig { params(actor: ::User, owner: ::Organization, kb: Orgs::CopilotSettings::ChatSettingsController::KbDeletionPayload).void }
      def instrument_knowledge_base_deleted(actor, owner, kb)
        instrument(::Copilot::Events::KNOWLEDGE_BASE_DELETED, {
          actor: actor,
          organization: owner,
          organization_id: owner.id,
          knowledge_base_id: kb[:id],
          knowledge_base_name: kb[:name],
        })
      end

      sig { params(actor: ::User, owner: ::Organization, kb: Orgs::CopilotSettings::ChatSettingsController::KbUpdatePayload).void }
      def instrument_knowledge_base_updated(actor, owner, kb)
        instrument(::Copilot::Events::KNOWLEDGE_BASE_UPDATED, {
          actor: actor,
          organization: owner,
          organization_id: owner.id,
          knowledge_base_id: kb[:id],
          knowledge_base_name: kb[:name],
          knowledge_base_description: kb[:description],
          number_of_repos: kb[:repos].count,
        })
      end
    end
  end
end
