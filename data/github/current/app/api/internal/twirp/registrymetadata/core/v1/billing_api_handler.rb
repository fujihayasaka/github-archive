# typed: true
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # Handler for the MonolithTwirp::Registrymetadata::Core::V1::BillingAPIService
      class BillingAPIHandler < Api::Internal::Twirp::Handler
        include Billing::RepositoryVisibility

        allow_access_for :client, allowed_clients: %w(packageregistry package_registry).freeze
        handles_service MonolithTwirp::Registrymetadata::Core::V1::BillingAPIService

        def before_rpc(rack_env, env)
          env[:request_client_ip] = rack_env["HTTP_X_CLIENT_IP"]
        end

        # Public: Implementation of the DownloadAllowed Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::DownloadAllowedRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::DownloadAllowedResponse, or a Twirp::Error.
        def download_allowed(req, env)
          org_or_user = get_org_or_user(req.actor_name)
          return Twirp::Error.not_found("org/user name not found") if org_or_user.nil?

          bytes = req.package_bytes
          return Twirp::Error.invalid_argument("must be non-empty", argument: "package_bytes") if bytes&.zero?

          billable_owner = org_or_user.billable_owner

          if billable_owner.customer&.packages_billed_on_billing_platform? || ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
            GitHub.logger.info(
              "Download allowed check for vNext billing",
              "code.namespace" => self.class.name,
              "code.function" => __method__,
            )

            # billable_owner is either User, Organization or Business
            customer_id = if billable_owner.delegate_billing_to_business?
              billable_owner.business.customer_id
            else
              billable_owner.customer&.id
            end

            return allowed_response if customer_id.nil?

            entity_detail = BillingPlatform::Base::EntityDetail.new(
              customerId: billable_owner.feature_enabled?(:use_find_or_create_customer) ? billable_owner.find_or_create_customer.id.to_s : customer_id.to_s,
              repoId: req.repo_id,
              ownerId: org_or_user.id,
              actorId: req.actor_id
            )

            repository = Repository.find_by(id: req.repo_id)

            GitHub.logger.info(
              "vNext billing entity detail",
              "code.namespace" => self.class.name,
              "code.function" => __method__,
              "customer_id" => customer_id,
              "repo_id" => req.repo_id,
              "owner_id" => org_or_user.id,
              "actor_id" => req.actor_id,
              "gh.repo.visibility" => repository&.visibility,
            )
            # convert bytes to gib
            size_in_gib = bytes.fdiv(1.gigabyte)

            # anonymous download has no actor_id
            if req.actor_id != 0
              actor = User.find_by(id: req.actor_id)
              if actor&.spammy?
                GitHub.dogstats.increment("packages.billing_api_handler.spammy_user_blocked")
                return rejected_response
              end
            end

            usage_key = BillingPlatform::Api::V1::UsageKey.new(
              product: "packages",
              sku: "packages_bandwidth",
              entityDetail: entity_detail,
              usageAt: Time.now.utc.to_i,
              repositoryVisibility: billing_repo_visibility(repository),
              quantity: size_in_gib # currently unused, see https://github.com/github/billing-platform/blob/main/docs/can_proceed_with_usage.md#usage
            )
            client = ::Billing::Platform::Api::Client.new
            response = client.can_proceed_with_usage(usage_key: usage_key)

            # If billing checks fail for any reason, we allow usage similar to actions. See https://github.com/github/package-registry-team/issues/8383
            if response.is_a?(Billing::Platform::Api::Error)
              GitHub.dogstats.increment("packages.billing_api_handler.download_allowed.error")

              GitHub.logger.info(
                "Failed to check if package download is allowed. Allowing download. Billing API error: #{response.message}",
                "customer_id" => customer_id,
                "repo_id" => req.repo_id,
                "owner_id" => org_or_user.id,
                "actor_id" => req.actor_id,
              )

              return allowed_response
            end

            GitHub.dogstats.increment("packages.billing_api_handler.download_allowed.success")
            return rejected_response unless response.is_a?(Hash) && response[:canProceed]

            allowed_response
          else

            return allowed_response if org_or_user.organization? && org_or_user.login == "github"

            permission = ::Billing::PackageRegistryPermission.new(org_or_user)
            return rejected_response unless permission.status[:allowed]

            # We do not bill for downloads via actions, so allow it.
            return allowed_response if env[:request_client_ip].present? && GitHub.actions_runner_ips_include?(env[:request_client_ip].split(",")[0])

            # we can assume package visibility is always private if we are here because RMS knows if a package is public and just won't call
            permission.download_allowed?(bytes: bytes, public: false) ? allowed_response : rejected_response
          end
        end

        # Public: Implementation of the StorageAllowed Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::StorageAllowedRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::StorageAllowedResponse, or a Twirp::Error.
        def storage_allowed(req, env)
          org_or_user = get_org_or_user(req.actor_name)
          return Twirp::Error.not_found("org/user name not found") if org_or_user.nil?

          bytes = req.package_bytes
          return Twirp::Error.invalid_argument("must be non-empty", argument: "package_bytes") if bytes&.zero?

          billable_owner = org_or_user.billable_owner

          if billable_owner.customer&.packages_billed_on_billing_platform? || ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
            GitHub.logger.info(
              "Storage allowed check for vNext billing",
              "code.namespace" => self.class.name,
              "code.function" => __method__,
            )

            # billable_owner is either User, Organization or Business
            customer_id = if billable_owner.delegate_billing_to_business?
              billable_owner.business.customer_id
            else
              billable_owner.customer&.id
            end

            return allowed_response if customer_id.nil?

            entity_detail = BillingPlatform::Base::EntityDetail.new(
              customerId: billable_owner.feature_enabled?(:use_find_or_create_customer) ? billable_owner.find_or_create_customer.id.to_s : customer_id.to_s,
              repoId: req.repo_id,
              ownerId: org_or_user.id,
              actorId: req.actor_id
            )

            repository = Repository.find_by(id: req.repo_id)

            GitHub.logger.info(
              "vNext billing entity detail",
              "code.namespace" => self.class.name,
              "code.function" => __method__,
              "customer_id" => customer_id,
              "repo_id" => req.repo_id,
              "owner_id" => org_or_user.id,
              "actor_id" => req.actor_id,
              "gh.repo.visibility" => repository&.visibility,
            )

            # convert bytes to gib
            size_in_gib = bytes.fdiv(1.gigabyte)

            usage_key = BillingPlatform::Api::V1::UsageKey.new(
              product: "packages",
              sku: "packages_storage",
              entityDetail: entity_detail,
              usageAt: Time.now.utc.to_i,
              repositoryVisibility: billing_repo_visibility(repository),
              quantity: size_in_gib # currently unused, see https://github.com/github/billing-platform/blob/main/docs/can_proceed_with_usage.md#usage
            )
            client = ::Billing::Platform::Api::Client.new
            response = client.can_proceed_with_usage(usage_key: usage_key)

            # If billing checks fail for any reason, we allow usage similar to actions. See https://github.com/github/package-registry-team/issues/8383
            if response.is_a?(Billing::Platform::Api::Error)
              GitHub.dogstats.increment("packages.billing_api_handler.storage_allowed.error")

              GitHub.logger.info(
                "Failed to check if package storage is allowed. Allowing storage. Billing API error: #{response.message}",
                "customer_id" => customer_id,
                "repo_id" => req.repo_id,
                "owner_id" => org_or_user.id,
                "actor_id" => req.actor_id,
              )

              return allowed_response
            end

            GitHub.dogstats.increment("packages.billing_api_handler.storage_allowed.success")
            return rejected_response unless response.is_a?(Hash) && response[:canProceed]

            allowed_response
          else
            return allowed_response if org_or_user.organization? && org_or_user.login == "github"

            permission = ::Billing::PackageRegistryPermission.new(org_or_user)
            return rejected_response unless permission.status[:allowed]

            GitHub.dogstats.time "packages.twirp_storage_allowed.storage_requested" do
              return permission.storage_allowed?(bytes: bytes, public: false) ? allowed_response : rejected_response
            end
          end
        end

        # Public: Implementation of the BillableNamespaces Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::BillableNamespacesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::BillableNamespacesResponse, or a Twirp::Error.
        def billable_namespaces(req, env)
          org_or_user = get_org_or_user(req.namespace)
          return Twirp::Error.not_found("org/user name not found") if org_or_user.nil?

          if org_or_user.try(:delegate_billing_to_business?)
            { namespaces: org_or_user.business.organizations.map { |o| o.name } }
          else
            { namespaces: [org_or_user.name] }
          end
        end

        # this is mainly so we can mock the returned owner in tests
        def get_org_or_user(name)
          User.find_by_login(name)
        end

        def allowed_response
          { is_allowed: { value: true } }
        end

        def rejected_response
          { is_allowed: { value: false } }
        end
      end
    end
  end
end
