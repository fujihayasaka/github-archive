# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    module PackagesPrerequisites
      include Billing::RepositoryVisibility
      extend self

      # Internal: Checks that a repository / owner and a viewer can use GitHub Packages.
      #
      # Explicitly does *not* check authn/authz. That is done in individual mutations.
      #
      # Returns a Hash shaped like a PackagesMutationResponse


      def check_repository_prerequisites(repository:, actor:, storage_requested: nil, feature_flags: [])
        success = true
        user_safe_status = :ok
        user_safe_message = "Request completed successfully."
        error_type = "none"

        success_response = {
          success: success,
          user_safe_status: user_safe_status,
          user_safe_message: user_safe_message,
          error_type:  "none",
        }

        owner = repository.owner
        billable_owner = owner.billable_owner

        GitHub.logger.info(
          "Billing vnext maven v1 upload check",
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repo.id" => repository.id,
          "gh.repo.visibility" => repository.visibility,
        )

        case
        when repository.locked?
          return {
            success: false,
            user_safe_status: :forbidden,
            user_safe_message: "Repository \"#{repository.name_with_display_owner}\" is locked and can't accept package uploads.",
            error_type: "repository_locked",
            validation_errors: [],
          }
        when repository.disabled?(viewer: actor) || repository.access.disabled?
          return {
            success: false,
            user_safe_status: :forbidden,
            user_safe_message: "Repository \"#{repository.name_with_display_owner}\" is disabled and can't accept package uploads.",
            error_type: "repository_disabled",
            validation_errors: [],
          }
        when repository.archived?
          return {
            success: false,
            user_safe_status: :forbidden,
            user_safe_message: "Repository \"#{repository.name_with_display_owner}\" is archived and can't accept package uploads.",
            error_type: "repository_archived",
            validation_errors: [],
          }
        when owner.spammy?
          return {
            success: false,
            user_safe_status: :forbidden,
            user_safe_message: "Repository \"#{repository.name_with_display_owner}\" can't accept package uploads.",
            error_type: "repository_spammy",
            validation_errors: [],
          }
        when owner.disabled?
          return {
            success: false,
            user_safe_status: :forbidden,
            user_safe_message: "The \"#{owner.display_login}\" account is disabled and can't accept package uploads.",
            error_type: "account_disabled",
            validation_errors: [],
          }
        when actor.spammy?
          GitHub.dogstats.increment("packages.packages_prerequisites.spammy_user_blocked")
          return {
            success: false,
            user_safe_status: :forbidden,
            user_safe_message: "Repository \"#{repository.name_with_display_owner}\" can't accept package uploads.",
            error_type: "user_spammy",
            validation_errors: [],
          }
        when actor.blocked_by?(owner)
          return {
            success: false,
            user_safe_status: :forbidden,
            user_safe_message: "You are blocked from publishing packages to the \"#{owner.display_login}\" account.",
            error_type: "user_blocked",
            validation_errors: [],
          }
        end

        # billable_owner is either User, Organization or Business
        customer_id = if billable_owner.delegate_billing_to_business?
          billable_owner.business.customer_id
        else
          billable_owner.customer&.id
        end

        if customer_id.nil?
          billable_owner.find_or_create_customer if billable_owner.feature_flag_enabled?(:use_find_or_create_customer, default: true)
          return success_response
        end

        entity_detail = BillingPlatform::Base::EntityDetail.new(
          customerId: customer_id.to_s,
          repoId: repository.id,
          ownerId: repository.owner.id, # Maven v1 will always have repo as owner
          actorId: actor.id
        )

        usage_key = BillingPlatform::Api::V1::UsageKey.new(
          product: "packages",
          sku: "packages_storage",
          entityDetail: entity_detail,
          repositoryVisibility: billing_repo_visibility(repository),
          usageAt: Time.now.utc.to_i
        )
        client = ::Billing::Platform::Api::Client.new
        response = client.can_proceed_with_usage(usage_key: usage_key)

        # If billing checks fail for any reason, we allow usage similar to actions. See https://github.com/github/package-registry-team/issues/8383
        if response.is_a?(Billing::Platform::Api::Error)
          GitHub.dogstats.increment("packages.packages_prerequisites.can_proceed_with_usage.error")

          GitHub.logger.info(
            "Failed to check can proceed with usage. Allowing usage. Billing API error: #{response.message}",
            "gh.customer.id" => customer_id,
            "gh.repo.id" => repository.id,
            "gh.repo.visibility" => repository.visibility,
            "gh.actor.id" => actor.id,
          )
        else
          GitHub.dogstats.increment("packages.packages_prerequisites.can_proceed_with_usage.success")

          unless response.is_a?(Hash) && response[:canProceed]
            success = false
            user_safe_status = :forbidden
            user_safe_message = "Repository \"#{repository.name_with_display_owner}\" can't accept package uploads. Please verify the billing status for this account."
            error_type = "billing_error"
          end
        end

        {
          success: success,
          user_safe_status: user_safe_status,
          user_safe_message: user_safe_message,
          error_type: error_type,
          validation_errors: [],
        }
      end
    end
  end
end
