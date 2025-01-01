# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Trials
      extend T::Helpers
      include Copilot::Businesses::Signatures

      abstract!

      sig { returns(T::Boolean) }
      def all_orgs_have_active_trial?
        ids = business_object.organization_ids
        count = ids.size

        Copilot::BusinessTrial
          .where(
            trialable_id: ids,
            trialable_type: "Organization",
          )
          .where.not(state: %w(expired canceled upgraded))
          .count == count && count > 0
      end

      sig { override.returns(T::Boolean) }
      def has_trial_organization?
        collect_metrics("copilot.has_trial_organization") do
          Copilot::BusinessTrial.exists?(
            trialable_id: business_object.organization_ids,
            trialable_type: "Organization"
          )
        end
      end

      sig { returns(T::Boolean) }
      def has_staff_created_trial_organization?
        Copilot::BusinessTrial.active.for_organization_ids(business_object.organization_ids).map do |trial|
          return true if trial.was_created_by_staff_user?
        end
        false
      end

      sig { override.returns(T::Array[Copilot::BusinessTrial]) }
      def organization_trials
        collect_metrics("copilot.trial_organizations") do
          Copilot::BusinessTrial.where(
            trialable_id: business_object.organization_ids,
            trialable_type: "Organization"
          ).to_a
        end
      end

      sig { returns(T::Array[Copilot::BusinessTrial]) }
      def ongoing_organization_trials
        collect_metrics("copilot.ongoing_organization_trials") do
          Copilot::BusinessTrial.ongoing.for_organization_ids(business_object.organization_ids).to_a
        end
      end

      sig { returns(T::Array[Copilot::Organization]) }
      def copilot_organizations_with_active_trials
        collect_metrics("copilot.copilot_organizations_with_active_trials") do
          Copilot::BusinessTrial.active.for_organization_ids(business_object.organization_ids).map do |trial|
            ::Copilot::Organization.new(trial.trialable)
          end
        end
      end

      # Copilot Enterprise trials are only offered at the organization level
      sig { returns(T::Boolean) }
      def on_free_copilot_enterprise_trial?
        false
      end

      # Cancels all ongoing Copilot Business trials for the organizations belonging to the business, and directly assigned Copilot seats.
      sig { params(actor: T.nilable(::User)).void }
      def cancel_copilot_business_access(actor)
        return unless business_object.dfd_trial?

        ongoing_organization_trials.each do |trial|
          trial.cancel!
        end

        if business_object.feature_flag_enabled?(:copilot_user_assignment_for_trials, default: false)
          Copilot::Seat.business_owned(business_object).find_each do |seat|
            seat.cancel!(reason: :enterprise_copilot_access_removed)
          end
        end

        copilot_business = Copilot::Business.new(business_object)
        copilot_business.disable_copilot! if business_object.feature_flag_enabled?(:copilot_licensing_for_trials, default: false)
      end

      # Enable Copilot Business trials for all organizations belonging to the business.
      # Only applicable if the business is on a GHE DFD trial, with the remaining trial days being greater than 0.
      # If the trial already exists, resume it. Otherwise, create a new one matching the GHE trial length of the business.
      sig { params(actor: ::User, skip_billable_check_on_trial_creation: T::Boolean).void }
      def create_or_resume_copilot_business_trials(actor, skip_billable_check_on_trial_creation: false)
        return unless business_object.trial?
        return unless business_object.dfd_trial?
        return unless business_object.trial_days_remaining.to_i > 0

        business_object.organizations.each do |org|
          create_or_resume_copilot_business_trial(actor, org, skip_billable_check_on_trial_creation:)
        end

        copilot_business = Copilot::Business.new(business_object)
        copilot_business.enable_copilot_for_all_organizations! if should_enable_copilot_for_all_organizations?(business: business_object)
      end

      sig { params(actor: ::User, org: ::Organization, skip_billable_check_on_trial_creation: T::Boolean).void }
      def create_or_resume_copilot_business_trial(actor, org, skip_billable_check_on_trial_creation: false)
        if business_trial = Copilot::Organization.new(org).business_trial
          business_trial.restart!  # Restart the trial if it already exists
        else
          Copilot::BusinessTrial.create_trial!(
            org,
            actor,
            trial_length: business_object.trial_days_remaining,
            copilot_plan: "business",
            skip_billable_check_on_trial_creation:,
          )
        end

        copilot_business = Copilot::Business.new(business_object)
        copilot_business.enable_copilot_for_all_organizations! if should_enable_copilot_for_all_organizations?(business: business_object)
      end

      # Upgrade all active Copilot Business trials for organizations belonging to the business, and Business-owned seats.
      sig { params(actor: T.nilable(::User)).void }
      def upgrade_copilot_business_access(actor)
        return unless should_upgrade_copilot_access?(business: business_object)

        ongoing_organization_trials.each do |trial|
          begin
            trial.upgrade!(actor)
          rescue Copilot::Errors::OrgTrialUpgradeError
            GitHub.logger.info(
              "Copilot business trial is not upgradable",
              "gh.copilot.business_trial.id" => trial.id,
              "gh.org.id" => trial.trialable.id,
            )
          end
        end

        copilot_business = Copilot::Business.new(business_object)
        copilot_business.enable_copilot_for_all_organizations! unless copilot_business.copilot_enabled_for_all_organizations?
      end

      sig { abstract.returns(::Business) }
      def business_object; end

      sig do
        abstract.type_parameters(:A).params(
          name: String,
          tags: T::Hash[Symbol, String],
          block: T.proc.returns(T.type_parameter(:A)),
        ).returns(T.type_parameter(:A))
      end
      def collect_metrics(name, **tags, &block); end

      private

      sig { params(business: T.nilable(::Business)).returns(T::Boolean) }
      def should_enable_copilot_for_all_organizations?(business:)
        return false unless business
        return false unless business.trial?
        return false unless business.feature_flag_enabled?(:copilot_licensing_for_trials, default: false)
        return false if Copilot::Business.new(business).copilot_enabled_for_all_organizations?
        business.organizations.any? || business.feature_flag_enabled?(:copilot_user_assignment_for_trials, default: false)
      end

      sig { params(business: T.nilable(::Business)).returns(T::Boolean) }
      def should_upgrade_copilot_access?(business:)
        return false unless business
        Copilot::Business.new(business).copilot_enabled_for_all_organizations? || business.has_ongoing_copilot_business_trial?
      end
    end
  end
end
