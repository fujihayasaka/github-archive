# typed: strict
# frozen_string_literal: true

module Abuse
  module Copilot
    class RunRequiredAuthorizationsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      schedule interval: 15.minutes, condition: -> { GitHub.copilot_for_business_enabled? }
      gate_with_feature_flag :copilot_required_authorizations_job
      exempt_from_tenant_context_requirement

      sig { void }
      def perform
        GitHub.logger.info("Starting Copilot required authorizations job")
        GitHub.logger.info("Loading organizations that need authorization")

        required_authorizations = ::Abuse::Copilot::RequiredAuthorization.active.where(owner_type: "Organization").includes(:owner)
        GitHub.logger.info("Loaded #{required_authorizations.count} required authorizations")
        GitHub.dogstats.distribution("copilot.auth_and_capture.required_authorizations",
          required_authorizations.count)

        required_authorizations.each do |required_authorization|
          GitHub.logger.with_named_tags("gh.org.id" => required_authorization.owner_id, "gh.copilot.required_authorization.id" => required_authorization.id) do
            GitHub.logger.info("Processing organization for auth #{required_authorization.id}")

            # As a last-ditch way to prevent the queue of authorizations from filling up, we want to
            # cancel any authorizations that have been unrunnable for over a month
            if required_authorization.created_at < 1.month.ago
              delete_required_auth(required_authorization, "too_old")
              next
            end

            organization = required_authorization.owner

            if organization.nil?
              delete_required_auth(required_authorization, "organization_deleted")
              next
            end

            # We want to cancel the required auth if an auth has happened since it was created
            has_been_authorized = if organization.customer
              existing_authorization = ::Billing::BillingTransaction
                .current_authorizations_for_customer(organization.customer.id)
                .last

              GitHub.logger.info("Got existing authorization with id #{existing_authorization&.id} and created_at #{existing_authorization&.created_at}")
              GitHub.logger.info("Required authorization created_at: #{required_authorization.created_at}")

              existing_authorization && (existing_authorization.created_at >= required_authorization.created_at)
            end

            if has_been_authorized
              delete_required_auth(required_authorization, "organization_authorized")
              next
            end

            # We want to cancel the required auth if we will never be able to fulfill it (e.g. the org is trusted)
            if !organization.can_be_authorized?(check_payment_method: true, check_overage: false)
              delete_required_auth(required_authorization, "organization_cannot_be_authed")
              next
            end

            # If the org belongs to a real GHEC business, we may never be able to auth it
            if organization.business && !organization.business.trial?
              delete_required_auth(required_authorization, "organization_owned_by_business")
              next
            end

            if organization.business && organization.business.digital_front_door?
              delete_required_auth(required_authorization, "organization_owned_by_business")
              next
            end

            GitHub.logger.info("Triggering authorization job for org")

            # Since we've already checked for a recent authorization, we can skip the previous authorizations check
            OrganizationAuthAndCaptureJob.perform_later(organization.id, skip_previous_authorizations_check: true, audit_log_reason: required_authorization.reason, skip_account_age_check: true)
          end
        end
      end

      sig { params(required_authorization: ::Abuse::Copilot::RequiredAuthorization, reason: String).void }
      def delete_required_auth(required_authorization, reason)
        GitHub.logger.info("Deleting required authorization", "gh.copilot.reason" => reason)

        with_write do
          required_authorization.destroy
        end
      end
    end
  end
end
