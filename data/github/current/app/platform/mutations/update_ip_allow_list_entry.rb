# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIpAllowListEntry < Platform::Mutations::Base
      description "Updates an IP allow list entry."

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      argument :ip_allow_list_entry_id, ID, "The ID of the IP allow list entry to update.", required: true, loads: Objects::IpAllowListEntry
      argument :allow_list_value, String, "An IP address or range of addresses in CIDR notation.", required: true
      argument :name, String, "An optional name for the IP allow list entry.", required: false
      argument :is_active, Boolean, "Whether the IP allow list entry is active when an IP allow list is enabled.", required: true

      field :ip_allow_list_entry, Objects::IpAllowListEntry, "The IP allow list entry that was updated.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, ip_allow_list_entry:, **inputs)
        owner = ip_allow_list_entry.owner
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

      def resolve(ip_allow_list_entry:, **inputs)
        ip_allow_list_entry.actor_ip = context[:ip]
        if ip_allow_list_entry.update \
          allow_list_value: inputs[:allow_list_value],
          name: inputs[:name],
          active: inputs[:is_active]
          { ip_allow_list_entry: ip_allow_list_entry }
        else
          raise Errors::Unprocessable.new(ip_allow_list_entry.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
