# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateIpAllowListEntry < Platform::Mutations::Base
      description "Creates a new IP allow list entry."

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      argument :owner_id, ID, "The ID of the owner for which to create the new IP allow list entry.", required: true, loads: Unions::IpAllowListOwner
      argument :allow_list_value, String, "An IP address or range of addresses in CIDR notation.", required: true
      argument :name, String, "An optional name for the IP allow list entry.", required: false
      argument :is_active, Boolean, "Whether the IP allow list entry is active when an IP allow list is enabled.", required: true

      field :ip_allow_list_entry, Objects::IpAllowListEntry, "The IP allow list entry that was created.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        if owner.is_a?(::Business)
          permission.access_allowed?(:administer_business,
            resource: owner, repo: nil, organization: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        elsif owner.is_a?(::Organization)
          permission.access_allowed?(:v4_manage_org_users,
            resource: owner, organization: owner, current_repo: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        elsif owner.is_a?(::Integration)
          permission.access_allowed?(
            :manage_github_app, resource: owner, organization: nil, current_repo: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(owner:, **inputs)
        viewer = context[:viewer]

        if owner.is_a?(::Business)
          unless owner.owner?(viewer)
            raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to create an IP allow list entry for this enterprise account.")
          end
        elsif owner.is_a?(::Organization)
          unless owner.adminable_by?(viewer)
            raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to create an IP allow list entry for this organization.")
          end
        elsif owner.is_a?(::Integration)
          unless owner.ip_allowlist_manageable_by?(viewer)
            raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to create an IP allow list entry for this GitHub App.")
          end
        end

        entry = owner.ip_allowlist_entries.new \
          allow_list_value: inputs[:allow_list_value],
          name: inputs[:name],
          active: inputs[:is_active]
        entry.actor_ip = context[:ip]
        if entry.save
          { ip_allow_list_entry: entry }
        else
          raise Errors::Unprocessable.new(entry.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
