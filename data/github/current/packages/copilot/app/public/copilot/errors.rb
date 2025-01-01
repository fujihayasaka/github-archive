# typed: strict
# frozen_string_literal: true

module Copilot
  module Errors
    class CopilotError < StandardError

      sig { returns(T::Hash[T.any(Symbol, String), T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
      attr_reader :payload

      sig { params(msg: String, payload: T.untyped).void } # rubocop:disable Sorbet/ForbidTUntyped
      def initialize(msg, **payload)
        @payload = payload
        super(msg)
      end

      sig do
        params(error: StandardError).returns(Copilot::Errors::CopilotError)
      end
      def self.from_error(error)
        copilot_error = new(error.message)
        copilot_error.set_backtrace(error.backtrace)
        copilot_error
      end
    end

    class AccessCheckError < CopilotError; end
    class AggregateUsageDetailsError < CopilotError; end
    class BillingPlatformError < CopilotError; end
    class BillingReconciliationError < CopilotError; end
    class BusinessCannotBeCleanedError < CopilotError; end
    class ContentExclusionError < CopilotError; end
    class CodingGuidelinesError < CopilotError; end
    class EMUInvitationError < CopilotError; end
    class EnterpriseJobError < CopilotError; end
    class EnterpriseTeamSeatAssignmentExistsError < CopilotError; end
    class EnterpriseTrialSyncError < CopilotError; end
    class ExternalIdentityUserMismatchError < CopilotError; end
    class LimitedUserError < CopilotError; end
    class MissingBusinessError < CopilotError; end
    class MissingEnterpriseTeamError < CopilotError; end
    class MissingEnterpriseTeamSeatAssignmentError < CopilotError; end
    class MissingExternalIdentityError < CopilotError; end
    class MultipleCustomers < CopilotError; end
    class MultipleSeatsForAssignableError < CopilotError; end
    class NoCustomer < CopilotError; end
    class OrganizationCannotBeCleanedError < CopilotError; end
    class OrganizationInvitationError < CopilotError; end
    class OrganizationResolutionError < CopilotError; end
    class OrgTransformFromIndividualError < CopilotError; end
    class OrgTrialSyncError < CopilotError; end
    class OrgTrialUpgradeError < CopilotError; end
    class SeatAssignmentAssignableError < CopilotError; end
    class SeatAssignmentConversionError < CopilotError; end
    class SeatAssignmentError < CopilotError; end
    class SeatAssignmentInvalidOwnerTypeError < CopilotError; end
    class SeatAssignmentPendingCancellationError < CopilotError; end
    class SeatCreationError < CopilotError; end
    class SeatCreationLockError < CopilotError; end
    class SeatCreationThrottleError < CopilotError; end
    class SeatDestructionError < CopilotError; end
    class SeatEmissionError < CopilotError; end
    class SeatEmissionOrganizationMissingError < CopilotError; end
    class SeatHistoryExistsError < CopilotError; end
    class SeatManagementError < CopilotError; end
    class SeatNotFoundError < CopilotError; end
    class SignupError < CopilotError; end
    class StatsError < CopilotError; end
    class TeamSyncError < CopilotError; end
    class TokenFailureError < CopilotError; end
    class UnknownAssignableTypeError < CopilotError; end
    class UsageMetricsApiError < CopilotError; end
    class UserCannotBeCleanedError < CopilotError; end


  end
end
