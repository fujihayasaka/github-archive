# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module Prebuilds
    WORKFLOW_NAME = "Codespaces Prebuilds"
    WORKFLOW_SLUG = "create_codespaces_prebuilds"

    module AvailabilityStatus
      NONE = "none"
      IN_PROGRESS = "in_progress"
      READY = "ready"
    end

    class PrebuildUsageLimitReached < Codespaces::Error; end

    # Whether prebuilds are actively enabled+configured on the repo
    def self.configured?(repository)
      return false if repository.nil?

      return false unless repository.owner&.codespaces_feature_enabled?

      return true if PrebuildConfiguration.where(repository: repository).exists?

      false
    end

    # Whether the billable owner has prebuild entitlements or spending limit available
    def self.prebuild_usage_allowed?(billable_owner)
      return false unless billable_owner.present?
      return false if billable_owner.spammy?
      Codespaces::AccessChecker.new(billable_owner, fast_timeout: false).prebuild_allowed?
    end

    # prebuild_usage_result - instance of Codespaces::Access::AllowedResult
    def self.prebuild_usage_disallowed_message(billable_owner, repository)
      result = Codespaces::AccessChecker.new(billable_owner, repository:).calculate_prebuild_allowed
      return if result.allowed?

      message = "Prebuilds are currently disabled because "

      additional_context = if result.disallowed_by_payment_method?
        if billable_owner.organization?
          "#{repository.owner.display_login} has an issue with its payment method. Please contact an administrator to enable prebuilds."
        else
          "there seems to be an issue with your payment method. You can adjust it in billing settings."
        end
      else
        if result.disallowed_by_entitlements?
          "you've reached your Codespaces included usage for this period. You can adjust it in billing settings."
        else # If we've hit this case, the only remaining option is that the billable owner hit their spending limit
          if billable_owner.organization?
            "#{repository.owner.display_login} has reached its Codespaces spending limit for this period. Please contact an administrator to enable prebuilds."
          else
            "you've reached your Codespaces spending limit for this period. You can adjust it in billing settings."
          end
        end
      end

      message += additional_context
    end

    # === Prebuild workflow helpers ===

    def self.workflow_path(vscs_target)
      Actions::Workflow.build_dynamic_workflow_path(
        Apps::Privileged::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME,
        workflow_slug(vscs_target),
      )
    end

    def self.workflow_slug(vscs_target)
      append_non_production_suffix(
        base: WORKFLOW_SLUG,
        suffix: "_#{vscs_target}",
        vscs_target: vscs_target
      )
    end

    def self.workflow_name(vscs_target)
      append_non_production_suffix(
        base: WORKFLOW_NAME,
        suffix: " (#{vscs_target})",
        vscs_target: vscs_target
      )
    end

    def self.append_non_production_suffix(base:, suffix:, vscs_target:)
      base = "#{base}"
      base += "#{suffix}" if vscs_target && vscs_target != :production
      base
    end

    def self.prebuild_hash_change?(repository:, current_oid:, new_oid:, devcontainer_path: nil)
      new_prebuild_hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: new_oid, devcontainer_path: devcontainer_path)
      current_prebuild_hash = Codespaces::CalculatePrebuildHash.call(repository: repository, oid: current_oid, devcontainer_path: devcontainer_path)
      current_prebuild_hash != new_prebuild_hash
    end

  end
end
