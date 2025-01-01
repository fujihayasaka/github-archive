# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseBillingInfo < Platform::Objects::Base
      description "Enterprise billing information visible to enterprise billing managers and owners."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, business)
        permission.access_allowed?(:manage_business_billing, resource: business, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.billing_manager?(permission.viewer) || object.owner?(permission.viewer) || permission.viewer&.site_admin?
      end

      minimum_accepted_scopes ["manage_billing:enterprise"]


      # BILLING FIELDS

      field :total_licenses, Integer, description: "The total number of licenses allocated.", null: false

      def total_licenses
        @object.async_organizations.then do
          @object.total_purchased_licenses
        end
      end

      field :total_available_licenses, Integer, description: "The number of available licenses across all owned organizations based on the unique number of billable users.", null: false

      def total_available_licenses
        Promise.all([@object.async_organizations, @object.async_license_usage, @object.async_customer]).then do
          @object.available_invitable_licenses
        end
      end

      field :all_licensable_users_count, Integer, description: "The number of licenseable users/emails across the enterprise.", null: false

      def all_licensable_users_count
        Promise.all([@object.async_organizations, @object.async_license_usage]).then do
          @object.consumed_invitable_licenses
        end
      end

      field :asset_packs, Integer, description: "The number of data packs used by all organizations owned by the enterprise.", null: false

      def asset_packs(**arguments)
        @object.aggregated_asset_status[:asset_packs]
      end

      field :bandwidth_usage, Float, description: "The bandwidth usage in GB for all organizations owned by the enterprise.", null: false

      def bandwidth_usage(**arguments)
        @object.aggregated_asset_status[:bandwidth_usage]
      end

      field :bandwidth_quota, Float, description: "The bandwidth quota in GB for all organizations owned by the enterprise.", null: false

      def bandwidth_quota(**arguments)
        @object.aggregated_asset_status[:bandwidth_quota]
      end

      field :bandwidth_usage_percentage, Integer, description: "The bandwidth usage as a percentage of the bandwidth quota.", null: false

      field :storage_usage, Float, description: "The storage usage in GB for all organizations owned by the enterprise.", null: false

      def storage_usage(**arguments)
        @object.aggregated_asset_status[:storage_usage]
      end

      field :storage_quota, Float, description: "The storage quota in GB for all organizations owned by the enterprise.", null: false

      def storage_quota(**arguments)
        @object.aggregated_asset_status[:storage_quota]
      end

      field :storage_usage_percentage, Integer, description: "The storage usage as a percentage of the storage quota.", null: false
    end
  end
end
