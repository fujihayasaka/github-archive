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

      # Cancels all ongoing Copilot Business trials for the organizations belonging to the business.
      sig { params(actor: ::User).void }
      def cancel_copilot_business_trials(actor)
        return unless business_object.dfd_trial?

        ongoing_organization_trials.each do |trial|
          trial.cancel!
        end
      end

      # Enable Copilot Business trials for all organizations belonging to the business.
      # Only applicable if the business is on a GHE DFD trial, with the remaining trial days being greater than 0.
      # If the trial already exists, resume it. Otherwise, create a new one matching the GHE trial length of the business.
      sig { params(actor: ::User).void }
      def create_or_resume_copilot_business_trials(actor)
        return unless business_object.trial?
        return unless business_object.dfd_trial?
        return unless business_object.trial_days_remaining.to_i > 0

        business_object.organizations.each do |org|
          create_or_resume_copilot_business_trial(actor, org)
        end
      end

      sig { params(actor: ::User, org: ::Organization).returns(T.any(TrueClass, FalseClass, Copilot::BusinessTrial)) }
      def create_or_resume_copilot_business_trial(actor, org)
        if business_trial = Copilot::Organization.new(org).business_trial
          business_trial.restart!  # Restart the trial if it already exists
        else
          Copilot::BusinessTrial.create_trial!(
            org,
            actor,
            trial_length: business_object.trial_days_remaining,
            copilot_plan: "business",
          )
        end
      end

      # Upgrade all active Copilot Business trials for organizations belonging to the business.
      sig { params(actor: ::User).void }
      def upgrade_copilot_business_trials(actor)
        return unless business_object.dfd_trial?

        copilot_organizations_with_active_trials.each do |org|
          org.business_trial&.upgrade!(actor)
        end  # TODO add enterprise-level instrumentation
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
    end
  end
end
