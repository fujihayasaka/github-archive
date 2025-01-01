# typed: strict
# frozen_string_literal: true

module Copilot
  module BusinessTrials
    class OrganizationTrialSyncJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_business_trial_job

      VALID_ACTIONS = T.let(%i[
        EXTENDED
        EXPIRED
      ], T::Array[Symbol])

      # this job will check if the GHEC
      sig do
        params(
          organization_id: Integer,
          action: Symbol,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def perform(organization_id, action, transaction_id, payload)
        raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

        organization = ::Organization.find_by(id: organization_id)
        return handle_copilot_error(Copilot::Errors::OrgTrialSyncError.new("Invalid Organization"), { "gh.organization.id" => organization_id }) unless organization

        trial = Copilot::BusinessTrial.for_organization(organization)
        return handle_copilot_error(Copilot::Errors::OrgTrialSyncError.new("No Trial For Organization"), { "gh.organization.id" => organization_id }) unless trial

        case action
        when :EXTENDED
          sync_cfb_trial(trial, organization)
        when :EXPIRED
          cancel_cfb_trial(trial)
        else
          raise ArgumentError, "Invalid action: #{action}"
        end
      end

      sig { params(trial: Copilot::BusinessTrial).void }
      def cancel_cfb_trial(trial)
        with_write do
          trial.cancel!
        end
      end

      sig { params(trial: Copilot::BusinessTrial, organization: ::Organization).void }
      def sync_cfb_trial(trial, organization)
        cloud_trial = ::Billing::EnterpriseCloudTrial.new(organization)

        return handle_copilot_error(Copilot::Errors::OrgTrialSyncError.new("No Cloud Trial For Organization"), { "gh.organization.id" => organization.id }) unless cloud_trial.active? && cloud_trial.expires_on.present?

        with_write do
          trial.update_expiration!(T.must(cloud_trial.expires_on))
        end
      end
    end
  end
end
