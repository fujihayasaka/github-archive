# typed: strict
# frozen_string_literal: true

module Copilot
  module BusinessTrials
    class EnterpriseTrialSyncJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_business_trial_job

      VALID_ACTIONS = T.let(%i[
        CANCELLED
        EXPIRED
        EXTENDED
        RESET
        UPGRADED
      ], T::Array[Symbol])

      # this job will check if the GHEC
      sig do
        params(
          business_id: Integer,
          action: Symbol,
          actor: T.nilable(::User),
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def perform(business_id, action, actor, transaction_id, payload)
        raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

        business = ::Business.find_by(id: business_id)
        return handle_copilot_error(Copilot::Errors::EnterpriseTrialSyncError.new("Invalid Business"), { "gh.business.id" => business_id }) unless business

        copilot_business = Copilot::Business.new(business)

        return GitHub.logger.info("No trial organizations found") unless copilot_business.has_trial_organization?

        case action
        when :CANCELLED, :EXPIRED
          cancel_cfb_trial(copilot_business)
        when :UPGRADED
          upgrade_cfb_trial(copilot_business, actor)
        when :EXTENDED, :RESET
          sync_cfb_trial(copilot_business)
        else
          raise ArgumentError, "Invalid action: #{action}"
        end
      end

      sig { params(copilot_business: Copilot::Business).void }
      def cancel_cfb_trial(copilot_business)
        GitHub.logger.info("Canceling CFB trials")
        with_write do
          copilot_business.organization_trials.each do |trial|
            trial.cancel!
          end
        end
      end

      sig do
        params(
          copilot_business: Copilot::Business,
          actor: T.nilable(::User),
          ).void
      end
      def upgrade_cfb_trial(copilot_business, actor)
        GitHub.logger.info("Upgrading CFB trials", "gh.user.id" => actor&.id)
        with_write do
          copilot_business.organization_trials.each do |trial|
            begin
              trial.upgrade!(actor)
            rescue Copilot::Errors::OrgTrialUpgradeError
              GitHub.logger.info(
                "Copilot business trial is not upgradable",
                "gh.copilot.business_trial.id" => trial.id,
                "gh.organization.id" => trial.trialable.id,
              )
            end
          end
        end
      end

      sig { params(copilot_business: Copilot::Business).void }
      def sync_cfb_trial(copilot_business)
        return handle_copilot_error(Copilot::Errors::EnterpriseTrialSyncError.new("No trial expiration date for business"), { "gh.business.id" => copilot_business.id }) unless copilot_business.business_object.trial_expires_at

        GitHub.logger.info("Syncing CFB trials")

        with_write do
          copilot_business.organization_trials.each do |trial|
            trial.update_expiration!(T.must(copilot_business.business_object.trial_expires_at).to_date)
          end
        end
      end
    end
  end
end
