# typed: true
# frozen_string_literal: true

# Values and configuration common to all internal Apps.
module Apps
  class Privileged
    class AllPrivilegedApps
      # Internal: The set of IntegrationsContollerMethods controller actions
      # that non site admins are allowed to view in the context of all Privileged
      # Apps.
      def self.allowed_integrations_controller_actions_for_non_site_admins
        # Currently this is identical to site admins because internal Apps can
        # _only_ be owned by GitHub and any admin modifying them would need to
        # have: a) `staff` role and b) access to the `employees` team.
        allowed_integrations_controller_actions_for_site_admins
      end

      # Internal: The set of IntegrationsContollerMethods controller actions
      # that site admins are allowed to view in the context of all Privileged
      # Apps.
      def self.allowed_integrations_controller_actions_for_site_admins
        %w[
          advanced
          beta_features
          beta_toggle
          generate_client_secret
          generate_key
          keys
          permissions
          remove_key
          revoke_all_tokens
          remove_client_secret
          show
          update
          update_permissions
        ]
      end
    end
  end
end
