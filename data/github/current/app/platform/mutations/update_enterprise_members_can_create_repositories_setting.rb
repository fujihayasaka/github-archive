# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseMembersCanCreateRepositoriesSetting < Platform::Mutations::Base
      description "Sets the members can create repositories setting for an enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the members can create repositories setting.", required: true, loads: Objects::Enterprise

      # NOTE: This argument is deprecated in favor of the granular boolean flags below and will be removed in the future.
      #       New code should use those arguments instead.
      argument :setting_value, Enums::EnterpriseMembersCanCreateRepositoriesSettingValue,
        "Value for the members can create repositories setting on the enterprise. This or the granular public/private/internal allowed fields (but not both) must be provided.",
        required: false

      argument :members_can_create_repositories_policy_enabled, Boolean, "When false, allow member organizations to set their own repository creation member privileges.", required: false
      argument :members_can_create_public_repositories, Boolean, "Allow members to create public repositories. Defaults to current value.", required: false
      argument :members_can_create_private_repositories, Boolean, "Allow members to create private repositories. Defaults to current value.", required: false
      argument :members_can_create_internal_repositories, Boolean, "Allow members to create internal repositories. Defaults to current value.", required: false

      field :enterprise, Objects::Enterprise, "The enterprise with the updated members can create repositories setting.", null: true
      field :message, String, "A message confirming the result of updating the members can create repositories setting.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        validate_input(inputs)

        ensure_business_can_use_api!(enterprise)
        business_full_plan_required!(enterprise)

        viewer = context[:viewer]
        unless enterprise.owner?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the members can create repositories setting on this enterprise.")
        end

        message = ""
        public_visibility = nil
        private_visibility = nil
        internal_visibility = nil

        enabled_visibilities = if inputs[:setting_value]
          enterprise.legacy_graphql_set_repo_creation_permissions(inputs[:setting_value], viewer)
        elsif inputs[:members_can_create_repositories_policy_enabled] == false
          enterprise.clear_members_can_create_repositories(actor: viewer)
        else
          enterprise.allow_members_can_create_repositories_with_visibilities(
            force: true,
            actor: viewer,
            public_visibility: inputs[:members_can_create_public_repositories],
            private_visibility: inputs[:members_can_create_private_repositories],
            internal_visibility: inputs[:members_can_create_internal_repositories],
          )
        end

        {
          enterprise: enterprise,
          message: returned_message(enabled_visibilities),
        }
      end

      private

      def validate_input(inputs)
        old_arg_provided = !inputs[:setting_value].nil?
        new_arg_provided = !inputs[:members_can_create_repositories_policy_enabled].nil? || !inputs[:members_can_create_public_repositories].nil? || !inputs[:members_can_create_private_repositories].nil? || !inputs[:members_can_create_internal_repositories].nil?
        raise Errors::Unprocessable.new("You cannot provide both settingValue and any members_can_create_* fields.") if old_arg_provided && new_arg_provided
        raise Errors::Unprocessable.new("You must provide either settingValue or members_can_create_* fields.") unless old_arg_provided || new_arg_provided
      end

      def returned_message(enabled_visibilities)
        if enabled_visibilities.nil?
          "Organization administrators can now change this setting for individual organizations."
        elsif enabled_visibilities.present?
          "Members can now create #{to_sentence(enabled_visibilities)} repositories."
        else
          "Members can no longer create repositories."
        end
      end

      def to_sentence(arr)
        return arr.first if arr.length == 1

        string = arr[0..-2].join(", ")
        string += "," if arr.length > 2 # Oxford commas keep it classy
        string += " and "
        string += arr.last

        string
      end
    end
  end
end
