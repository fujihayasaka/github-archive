# typed: strict
# frozen_string_literal: true

module Copilot
  class ErrorReporter
    extend T::Sig

    # this allows us to pass in any of the copilot objects to pass to Sentry
    sig do
      params(
        error: T.any(StandardError, Copilot::Errors::CopilotError),
        copilot_business: T.nilable(Copilot::Business),
        copilot_business_trial: T.nilable(Copilot::BusinessTrial),
        copilot_configuration: T.nilable(Copilot::Configuration),
        copilot_editor_notification: T.nilable(Copilot::EditorNotification),
        copilot_free_user: T.nilable(Copilot::FreeUser),
        copilot_organization: T.nilable(Copilot::Organization),
        copilot_seat_assignment: T.nilable(Copilot::SeatAssignment),
        copilot_seat: T.nilable(Copilot::Seat),
        copilot_user: T.nilable(T.any(Copilot::User, ::User)),
        app: String,
        catalog_service: String,
        extra_details: T::Hash[T.any(Symbol, String), T.any(String, Integer, Date, T::Boolean, T.nilable(Integer))]).
      void
    end
    def self.report!(
      error,
      copilot_business: nil,
      copilot_business_trial: nil,
      copilot_configuration: nil,
      copilot_editor_notification: nil,
      copilot_free_user: nil,
      copilot_organization: nil,
      copilot_seat_assignment: nil,
      copilot_seat: nil,
      copilot_user: nil,
      app: "copilot-dotcom",
      catalog_service: "github/copilot",
      extra_details: Hash.new
    )
      payload = Copilot::ErrorPayload.new(
        copilot_business: copilot_business,
        copilot_business_trial: copilot_business_trial,
        copilot_configuration: copilot_configuration,
        copilot_editor_notification: copilot_editor_notification,
        copilot_free_user: copilot_free_user,
        copilot_organization: copilot_organization,
        copilot_seat_assignment: copilot_seat_assignment,
        copilot_seat: copilot_seat,
        copilot_user: copilot_user,
      ).normalize

      extra_details[:app]             = app
      extra_details[:catalog_service] = catalog_service

      payload.merge!(extra_details)

      error.set_backtrace(caller) if error.backtrace.nil?

      Failbot.report!(
        error,
        payload
      )
    end
  end
end
