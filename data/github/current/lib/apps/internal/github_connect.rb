# typed: true
# frozen_string_literal: true

# GitHub Connect Apps are created on-demand for Enterprise customers and are
# not technically configurable in the internal registry like other internal
# Apps (which have a single canonical database record).
#
# However, there is some special-case behavior for GitHub Connect and this file
# serves as a repository for some of those values.
module Apps
  class Internal
    class GitHubConnect
      # Internal: The set of IntegrationsContollerMethods controller actions
      # that non site admins are allowed to view in the context of a GitHub
      # Connect App.
      def self.allowed_integrations_controller_actions_for_non_site_admins
        %w[
          advanced
          installations
          keys
          permissions
          show
        ]
      end

      # Internal: The set of IntegrationsContollerMethods controller actions
      # that site admins are allowed to view in the context of a GitHub Connect
      # App.
      #
      # This is a super-set containing actions for non-site admins.
      def self.allowed_integrations_controller_actions_for_site_admins
        allowed_integrations_controller_actions_for_non_site_admins +
          %w[
            generate_key
            remove_key
            update
            update_permissions
          ]
      end
    end
  end
end
