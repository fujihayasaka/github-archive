# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackageFile < Platform::Objects::Base
      model_name "Registry::File"
      description "A file in a package version."

      minimum_accepted_scopes ["read:packages"]
      visibility :public, environments: [:enterprise, :dotcom]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, package_file)
        package_file.async_package_version.then do |package_version|
          permission.typed_can_access?("PackageVersion", package_version)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_package_version.then do |package_version|
          permission.typed_can_see?("PackageVersion", package_version)
        end
      end

      implements_node templates: [
        [:rpf, :repo_id, :package_file_id]
      ],
      as: "PF", ready_date: "2021-07-01" do |package_file|
        package_file.async_package_version.then do |package_version|
          package_version.async_package.then do |package|
            package.async_repository.then do |repo|
              {
                prefix: :rpf,
                package_file_id: package_file.id,
                repo_id: repo.id,
              }
            end
          end
        end
      end

      database_id_field(visibility: :internal)

      updated_at_field

      field :guid, String, "A unique identifier for this file.", null: true, visibility: :internal
      field :md5, String, "MD5 hash of the file.", null: true
      field :name, String, description: "Name of the file.", null: false
      field :sha1, String, "SHA1 hash of the file.", null: true
      field :sha256, String, "SHA256 hash of the file.", null: true
      field :size, Integer, "Size of the file in bytes.", null: true
      field :sri, String, "Identifies the subresource integrity (SRI).", method: :sri_512, null: true, visibility: :internal

      # For S3->Azure Blob storage migration for Maven and possibly Docker v1->v2 migration stragglers
      field :object_migration_state, Enums::PackageFileObjectMigrationState, "An enum indicating whether this object is migrated or not.", null: false, visibility: :internal

      field :package_version, Objects::PackageVersion, description: "The package version this file belongs to.", null: true

      def package_version
        Loaders::PackageFiles.get_version(@object.package_version_id)
      end

      def name
        @object.async_package_version.then do |version|
          version.async_package.then do
            @object.name
          end
        end
      end

      field :billing_allowed, Boolean, description: "whether billing gives you access to the file", null: false, visibility: :internal

      def billing_allowed
        return true unless GitHub.billing_enabled? # Skip billing checks if billing is disabled.
        viewer = @context[:viewer]
        @object.async_package_version.then do |package_version|
          package_version.async_package.then do |package|
            package.async_repository.then do |repo|
              repo.async_owner.then do |owner|
                owner.async_customer.then do

                  billable_owner = owner.billable_owner

                  if billable_owner.customer&.packages_billed_on_billing_platform?
                    GitHub.logger.info(
                      "Billing vnext maven v1 download check - billing_allowed",
                      "code.namespace" => self.class.name,
                      "code.function" => __method__,
                    )

                    customer_id = if billable_owner.delegate_billing_to_business?
                      billable_owner.business.customer_id
                    else
                      billable_owner.customer&.id
                    end
                    return true if customer_id.nil?

                    entity_detail = BillingPlatform::Base::EntityDetail.new(
                      customerId: customer_id.to_s,
                      repoId: repo.id,
                      ownerId: owner.id,
                      actorId: viewer.id
                    )

                    # Only check for file download
                    # We are using file state to differentiate between upload/download scenarios
                    if @object.state == "uploaded"
                      usage_key = BillingPlatform::Api::V1::UsageKey.new(
                        product: "packages",
                        sku: "packages_bandwidth",
                        entityDetail: entity_detail,
                        usageAt: Time.now.utc.to_i,
                        quantity: @object.size # size of package in bytes
                      )
                      client = ::Billing::Platform::Api::Client.new
                      response = client.can_proceed_with_usage(usage_key: usage_key)

                      return false unless response.is_a?(Hash) && response[:canProceed]
                    end

                    true
                  else
                    permission = Billing::PackageRegistryPermission.new(owner)

                    unless permission.allowed?(public: repo.public?)
                      next false
                    end

                    unless Platform::Helpers::ViaActions.request_via_actions?(context: context, log_metric: true, usage_bytes: @object.size)
                      if !permission.download_allowed?(bytes: @object.size, public: repo.public?)
                        next false
                      end
                    end

                    true
                  end
                end
              end
            end
          end
        end
      end

      field :url, Scalars::URI, description: "URL to download the asset.", null: true

      def url
        viewer = @context[:viewer]
        @object.async_package_version.then do |package_version|
          package_version.async_package.then do |package|
            package.async_repository.then do |repo|
              repo.async_owner.then do |owner|
                owner.async_customer.then do

                  billable_owner = owner.billable_owner

                  if billable_owner.customer&.packages_billed_on_billing_platform?
                    GitHub.logger.info(
                      "Billing vnext maven v1 download check - url",
                      "code.namespace" => self.class.name,
                      "code.function" => __method__,
                    )

                    customer_id = if billable_owner.delegate_billing_to_business?
                      billable_owner.business.customer_id
                    else
                      billable_owner.customer&.id
                    end
                    return @object.url(actor: viewer, pv: package_version, owner: owner) if customer_id.nil?

                    entity_detail = BillingPlatform::Base::EntityDetail.new(
                      customerId: customer_id.to_s,
                      repoId: repo.id,
                      ownerId: owner.id,
                      actorId: viewer.id
                    )

                    # Only check for file download
                    # We are using file state to differentiate between upload/download scenarios
                    if @object.state == "uploaded"
                      usage_key = BillingPlatform::Api::V1::UsageKey.new(
                        product: "packages",
                        sku: "packages_bandwidth",
                        entityDetail: entity_detail,
                        usageAt: Time.now.utc.to_i,
                        quantity: @object.size # size of package in bytes
                      )
                      client = ::Billing::Platform::Api::Client.new
                      response = client.can_proceed_with_usage(usage_key: usage_key)

                      return nil unless response.is_a?(Hash) && response[:canProceed]
                    end

                    @object.url(actor: viewer, pv: package_version, owner: owner)
                  else
                    permission = Billing::PackageRegistryPermission.new(owner)
                    status = permission.status

                    next nil unless status[:allowed]

                    unless Platform::Helpers::ViaActions.request_via_actions?(context: context, log_metric: true, usage_bytes: @object.size)
                      if !permission.download_allowed?(bytes: @object.size, public: repo.public?)
                        next nil
                      end
                    end

                    @object.url(actor: viewer, pv: package_version, owner: owner)
                  end
                end
              end
            end
          end
        end
      end

      field :metadata_url, Scalars::URI, description: "URL to download the asset metadata.", null: true, visibility: :internal

      def metadata_url
        viewer = @context[:viewer]
        @object.async_package_version.then do |package_version|
          package_version.async_package.then do |package|
            package.async_repository.then do
              @object.metadata_url(actor: viewer)
            end
          end
        end
      end
    end
  end
end
