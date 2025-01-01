# typed: strict
# frozen_string_literal: true

module Copilot
  class ErrorPayload

    sig do
      params(
        copilot_business: T.nilable(T.any(Copilot::Business, ::Business)),
        copilot_business_trial: T.nilable(Copilot::BusinessTrial),
        copilot_configuration: T.nilable(Copilot::Configuration),
        copilot_editor_notification: T.nilable(Copilot::EditorNotification),
        copilot_free_user: T.nilable(Copilot::FreeUser),
        copilot_organization: T.nilable(T.any(Copilot::Organization, ::Organization)),
        copilot_seat_assignment: T.nilable(Copilot::SeatAssignment),
        copilot_seat: T.nilable(Copilot::Seat),
        copilot_user: T.nilable(T.any(Copilot::User, ::User)),
      ).void
    end
    def initialize(
      copilot_business: nil,
      copilot_business_trial: nil,
      copilot_configuration: nil,
      copilot_editor_notification: nil,
      copilot_free_user: nil,
      copilot_organization: nil,
      copilot_seat_assignment: nil,
      copilot_seat: nil,
      copilot_user: nil
    )
      @payload                 = T.let({}, T::Hash[T.untyped, T.untyped]) # rubocop:disable Sorbet/ForbidTUntyped
      @copilot_business        = copilot_business
      @copilot_business_trial  = T.let(copilot_business_trial, T.nilable(Copilot::BusinessTrial))
      @copilot_configuration   = T.let(copilot_configuration, T.nilable(Copilot::Configuration))
      @copilot_editor_notification = T.let(copilot_editor_notification, T.nilable(Copilot::EditorNotification))
      @copilot_free_user       = T.let(copilot_free_user, T.nilable(Copilot::FreeUser))
      @copilot_organization    = copilot_organization
      @copilot_seat_assignment = T.let(copilot_seat_assignment, T.nilable(Copilot::SeatAssignment))
      @copilot_seat            = T.let(copilot_seat, T.nilable(Copilot::Seat))
      @copilot_user            = copilot_user
    end

    sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def normalize
      add_business_details!
      add_business_trial_details!
      add_configuration_details!
      add_editor_notification_details!
      add_free_user_details!
      add_organization_details!
      add_seat_assignment_details!
      add_seat_details!
      add_user_details!

      @payload.compact
    end

    private

    sig { void }
    def add_business_details!
      return unless @copilot_business

      @payload["gh.business.id"] ||= @copilot_business.id
    end

    sig { void }
    def add_business_trial_details!
      return unless @copilot_business_trial

      @payload["gh.copilot.business_trial.id"] ||= @copilot_business_trial.id
      @payload["gh.copilot.business_trial.length"] ||= @copilot_business_trial.trial_length
      @payload["gh.copilot.business_trial.seat_count"] ||= 0 # trial.seat_count field will be deprecated soon
      @payload["gh.copilot.business_trial.started_at"] ||= @copilot_business_trial.started_at
      @payload["gh.copilot.business_trial.ends_at"] ||= @copilot_business_trial.ends_at
      @payload["gh.copilot.business_trial.managing_user.id"] ||= @copilot_business_trial.managing_user_id
    end

    sig { void }
    def add_configuration_details!
      return unless @copilot_configuration

      @payload["gh.copilot.configuration.id"] ||= @copilot_configuration.id
    end

    sig { void }
    def add_editor_notification_details!
      return unless @copilot_editor_notification

      @payload["gh.copilot.editor_notification.id"] ||= @copilot_editor_notification.id
    end

    sig { void }
    def add_free_user_details!
      return unless @copilot_free_user

      @payload["gh.copilot.free_user.id"]   ||= @copilot_free_user.id
      @payload["gh.copilot.free_user.type"] ||= @copilot_free_user.free_user_type
    end

    sig { void }
    def add_organization_details!
      return unless @copilot_organization

      @payload["gh.organization.id"] ||= @copilot_organization.id
    end

    sig { void }
    def add_seat_assignment_details!
      return unless @copilot_seat_assignment

      @payload["gh.copilot.seat_assignment.id"] ||= @copilot_seat_assignment.id
      @payload["gh.copilot.seat_assignment.owner.type"] ||= @copilot_seat_assignment.owner_type
    end

    sig { void }
    def add_seat_details!
      return unless @copilot_seat

      @payload["gh.copilot.seat.id"] ||= @copilot_seat.id
    end

    sig { void }
    def add_user_details!
      return unless @copilot_user

      @payload["gh.user.id"] ||= @copilot_user.id
    end
  end
end
