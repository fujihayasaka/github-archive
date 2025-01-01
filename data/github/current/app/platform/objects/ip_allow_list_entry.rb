# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IpAllowListEntry < Platform::Objects::Base
      model_name "IpAllowlistEntry"

      implements_node templates: [
        [:eiale, :enterprise_id, :ip_allow_list_entry_id],
        [:oiale, :org_id, :ip_allow_list_entry_id],
        [:uaiale, :user_id, :application_id, :ip_allow_list_entry_id],
        [:oaiale, :org_id, :application_id, :ip_allow_list_entry_id]],
        as: "IALE", ready_date: "2021-07-10" do |ip_allow_list_entry|

        ip_allow_list_entry.async_owner.then do |owner|
          case owner
          when ::Organization
            { prefix: :oiale, org_id: owner.id, ip_allow_list_entry_id: ip_allow_list_entry.id }
          when ::Business
            { prefix: :eiale, enterprise_id: owner.id, ip_allow_list_entry_id: ip_allow_list_entry.id }
          when ::Integration
            owner.async_owner.then do |integration_owner|
              case integration_owner.type
              when "User"
                { prefix: :uaiale, user_id: owner.owner.id, application_id: owner.id, ip_allow_list_entry_id: ip_allow_list_entry.id }
              when "Organization"
                { prefix: :oaiale, org_id: owner.owner.id, application_id: owner.id, ip_allow_list_entry_id: ip_allow_list_entry.id }
              else
                raise Platform::Errors::Internal, "Unexpected Integration owner type: #{integration_owner.inspect}"
              end
            end
          else
            raise Platform::Errors::Internal, "Unexpected IP allow list owner: #{owner.inspect}"
          end
        end
      end

      description "An IP address or range of addresses that is allowed to access an owner's resources."

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_owner.then do |owner|
          case owner
          when ::Business
            permission.access_allowed?(
              :administer_business, resource: owner, organization: nil, current_repo: nil,
              allow_integrations: false, allow_user_via_granular_actor: false)
          when ::Organization
            permission.access_allowed?(
              :v4_manage_org_users, resource: owner, organization: owner, current_repo: nil,
              allow_integrations: false, allow_user_via_granular_actor: false)
          when ::Integration
            owner.async_owner.then do
              permission.access_allowed?(
                :manage_github_app, resource: owner, organization: nil, current_repo: nil,
                allow_integrations: false, allow_user_via_granular_actor: false)
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Let site admins view all IP allow list entries
        return true if permission.viewer.site_admin?

        object.async_owner.then do |owner|
          case owner
          when ::Business
            owner.owner?(permission.viewer)
          when ::Organization
            owner.adminable_by?(permission.viewer)
          when ::Integration
            owner.async_owner.then do
              owner.ip_allowlist_manageable_by?(permission.viewer)
            end
          end
        end
      end

      field :owner, Unions::IpAllowListOwner, description: "The owner of the IP allow list entry.", null: false
      field :allow_list_value, String, description: "A single IP address or range of IP addresses in CIDR notation.", null: false
      field :name, String, description: "The name of the IP allow list entry.", null: true
      field :is_active, Boolean, method: :active?, description: "Whether the entry is currently active.", null: false
      created_at_field
      updated_at_field
    end
  end
end
