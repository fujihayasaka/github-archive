# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    module PackagesPrerequisites
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

        billable_owner = repository.owner.billable_owner

        if billable_owner.customer&.packages_billed_on_billing_platform?
          GitHub.logger.info(
            "Billing vnext maven v1 upload check",
            "code.namespace" => self.class.name,
            "code.function" => __method__,
          )

          # billable_owner is either User, Organization or Business
          customer_id = if billable_owner.delegate_billing_to_business?
            billable_owner.business.customer_id
          else
            billable_owner.customer&.id
          end

          return success_response if customer_id.nil?

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
            usageAt: Time.now.utc.to_i
          )
          client = ::Billing::Platform::Api::Client.new
          response = client.can_proceed_with_usage(usage_key: usage_key)

          unless response.is_a?(Hash) && response[:canProceed]
            success = false
            user_safe_status = :forbidden
            user_safe_message = "Repository \"#{repository.name_with_display_owner}\" can't accept package uploads. Please verify the billing status for this account."
            error_type = "billing_error"
          end
        else
          owner = repository.owner
          billing_permission = Billing::PackageRegistryPermission.new(owner)

          case
          when repository.locked?
            success = false
            user_safe_status = :forbidden
            user_safe_message = "Repository \"#{repository.name_with_display_owner}\" is locked and can't accept package uploads."
            error_type = "repository_locked"
          when repository.disabled?(viewer: actor) || repository.access.disabled?
            success = false
            user_safe_status = :forbidden
            user_safe_message = "Repository \"#{repository.name_with_display_owner}\" is disabled and can't accept package uploads."
            error_type = "repository_disabled"
          when repository.archived?
            success = false
            user_safe_status = :forbidden
            user_safe_message = "Repository \"#{repository.name_with_display_owner}\" is archived and can't accept package uploads."
            error_type = "repository_archived"
          when owner.spammy?
            success = false
            user_safe_status = :forbidden
            user_safe_message = "Repository \"#{repository.name_with_display_owner}\" can't accept package uploads."
            error_type = "repository_spammy"
          when owner.disabled?
            success = false
            user_safe_status = :forbidden
            user_safe_message = "The \"#{owner.display_login}\" account is disabled and can't accept package uploads."
            error_type = "account_disabled"
          when actor.spammy?
            success = false
            user_safe_status = :forbidden
            user_safe_message = "Repository \"#{repository.name_with_display_owner}\" can't accept package uploads."
            error_type = "user_spammy"
          when actor.blocked_by?(owner)
            success = false
            user_safe_status = :forbidden
            user_safe_message = "You are blocked from publishing packages to the \"#{owner.display_login}\" account."
            error_type = "user_blocked"
          when !billing_permission.allowed?(public: repository.public?)
            success = false
            user_safe_status = :forbidden
            user_safe_message = billing_permission.status[:error][:message] || "Please verify the billing status for this account."
            error_type = \
            case billing_permission.status[:error][:reason]
            when "DISABLED" then "account_disabled"
            when "PLAN_INELIGIBLE" then "plan_ineligible"
            when "TRADE_RESTRICTED_ORGANIZATION" then "trade_restriction"
            end
          when storage_requested
            GitHub.dogstats.time "packages.check_repository_prerequisites.storage_requested" do
              unless billing_permission.storage_allowed?(bytes: storage_requested, public: repository.public?)
                success = false
                user_safe_status = :forbidden
                user_safe_message = "This operation would exceed the storage allotment for this account."
                error_type = "resource_limited"
              end
            end
          end

          if success && feature_flags.any?
            feature_flags.each do |flag|
              unless GitHub.flipper[flag].enabled?(owner)
                success = false
                user_safe_status = :forbidden
                user_safe_message = "This GitHub Package Registry early access feature is not enabled for the \"#{owner.display_login}\" account."
                error_type = "feature_flag"
                next
              end
            end
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
