# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Trials
      extend T::Helpers
      extend T::Sig
      include Copilot::Businesses::Signatures

      abstract!

      sig { override.returns(T::Boolean) }
      def has_trial_organization?
        collect_metrics("copilot.has_trial_organization") do
          Copilot::BusinessTrial.exists?(
            trialable_id: business_object.organization_ids,
            trialable_type: "Organization"
          )
        end
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
