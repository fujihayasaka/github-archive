# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # We have four different events that we can receive.
    #
    # :cancel_invitation and :invite_expired are handled the same way - we get rid of the SeatAssignment if it exists.
    class OrganizationInvitationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      gate_with_feature_flag :copilot_seat_assignment_job

      VALID_ACTIONS = T.let(%i[
        cancel_invitation
        invite_expired
      ], T::Array[Symbol])

      sig do
        params(
          organization_id: Integer,
          invitation_id: Integer,
          action: Symbol,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          user_id: T.nilable(Integer),
        ).void
      end
      def perform(organization_id:, invitation_id:, action: :unknown, transaction_id: nil, payload: nil, user_id: nil)
        raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.org.id" => organization_id,
          "gh.org_invitation.id" => invitation_id,
          "gh.copilot.job_action" => action,
          "gh.transaction.id" => transaction_id,
          "gh.user.id" => user_id,
        ) do
          @organization_id = T.let(organization_id, T.nilable(Integer))
          @invitation_id   = T.let(invitation_id, T.nilable(Integer))
          @action          = T.let(action, T.nilable(Symbol))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @user_id         = T.let(user_id, T.nilable(Integer))

          # load up the organization - this is required so if it isn't there, report an exception. We might want to tweak this later
          @organization = T.let(::Organization.find_by(id: T.must(@organization_id)), T.nilable(::Organization))
          return report_error("Invalid Organization") unless @organization

          copilot_organization = Copilot::Organization.new(@organization)
          return GitHub.logger.info("Organization not enabled for CFB") unless copilot_organization.copilot_for_business_enabled?

          # load up the invitation - this is required so if it isn't there, report an exception.  We might want to tweak this later
          @invitation = T.let(::OrganizationInvitation.find_by(id: invitation_id), T.nilable(OrganizationInvitation))
          return report_error("Invalid Invitation") unless @invitation

          GitHub.dogstats.distribution_time("copilot.seat_management.org_invitation_job.duration") do
            GitHub.logger.info("Processing action #{action}")
            case action
            when :cancel_invitation, :invite_expired
              cancel_invitation
            else
              # i'm not sure how you got here, but you did and i congratulate you.
              # still an ArgumentError
              raise ArgumentError, "Invalid action: #{action}"
            end
          end
        end
      end

      # We received either the :cancel_invitation or :invite_expired events
      # Practically speaking, these are the same because the invitation no longer needs a SeatAssignment
      # Let's get rid of the SeatAssignment
      sig { void }
      def cancel_invitation
        GitHub.dogstats.distribution_time("copilot.seat_management.enterprise_job.cancel_invitation.duration") do
          GitHub.logger.info("Removing Invitation SeatAssignment")

          with_write do
            Copilot::SeatAssignment.where(
              organization: @organization,
              assignable: @invitation
            ).destroy_all
          end
        end
      end

      private

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.organization.id" => @organization_id,
          "gh.invitation.id" => @invitation_id,
          :action => @action,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.user.id" => @user_id,
        }
        handle_copilot_error(Copilot::Errors::OrganizationInvitationError.new(message), details)
      end
    end
  end
end
