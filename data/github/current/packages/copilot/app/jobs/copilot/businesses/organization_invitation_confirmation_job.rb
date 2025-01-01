# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    class OrganizationInvitationConfirmationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      gate_with_feature_flag :copilot_business_invitation_confirmation_job

      VALID_ACTIONS = T.let(%i[
        confirm_invitation
      ], T::Array[Symbol])

      sig do
        params(
          organization_id: Integer,
          invitation_id: Integer,
          business_id: Integer,
          action: Symbol,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def perform(organization_id:, invitation_id:, business_id:, action: :unknown, transaction_id: nil, payload: nil)
        raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.org.id" => organization_id,
          "gh.org_invitation.id" => invitation_id,
          "gh.copilot.job_action" => action,
          "gh.transaction.id" => transaction_id,
          "gh.business.id" => business_id
        ) do
          @organization_id = T.let(organization_id, T.nilable(Integer))
          @invitation_id   = T.let(invitation_id, T.nilable(Integer))
          @business_id     = T.let(business_id, T.nilable(Integer))
          @action          = T.let(action, T.nilable(Symbol))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped

          # load up the organization - this is required so if it isn't there, report an exception. We might want to tweak this later
          @organization = T.let(::Organization.find_by(id: T.must(@organization_id)), T.nilable(::Organization))
          return report_error("Invalid Organization") unless @organization

          copilot_organization = Copilot::Organization.new(@organization)
          return GitHub.logger.info("Organization not enabled for CFB") unless copilot_organization.copilot_for_business_enabled?

          # load up the invitation - this is required so if it isn't there, report an exception.  We might want to tweak this later
          @invitation = T.let(::BusinessOrganizationInvitation.find_by(id: invitation_id), T.nilable(BusinessOrganizationInvitation))
          return report_error("Invalid Invitation") unless @invitation

          @business = T.let(::Business.find_by(id: T.must(@business_id)), T.nilable(::Business))
          return report_error("Invalid business") unless @business

          GitHub.dogstats.distribution_time("copilot.businesses.org_invitation_confirmation_job.duration") do
            GitHub.logger.info("Processing action #{action}")
            if action == :confirm_invitation
              confirm_invitation
            else
              raise ArgumentError, "Invalid action: #{action}"
            end
          end
        end
      end

      sig { void }
      def confirm_invitation
        with_write do
          GitHub.dogstats.distribution_time("copilot.businesses.enterprise_job.confirm_invitation.duration") do
            GitHub.logger.info("Propagating settings on organization invite")

            copilot_business = ::Copilot::Business.new(T.must(@business))

            if copilot_business.copilot_enabled_for_all_organizations?
              copilot_business.propagate_settings_for_org!(Copilot::Organization.new(T.must(@organization)))
            end
          end
        end
      end

      private

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.organization.id" => @organization_id,
          "gh.invitation.id" => @invitation_id,
          "gh.business.id" => @business_id,
          :action => @action,
          :transaction_id => @transaction_id,
          :payload => @payload,
        }
        handle_copilot_error(Copilot::Errors::OrganizationInvitationError.new(message), details)
      end
    end
  end
end
