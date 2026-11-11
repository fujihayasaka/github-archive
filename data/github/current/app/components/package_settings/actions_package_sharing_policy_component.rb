# typed: true
# frozen_string_literal: true

module PackageSettings
  class ActionsPackageSharingPolicyComponent < ApplicationComponent
    include TextHelper

    def initialize(package:)
      @package = package
    end

    attr_reader :package

    def actions_package_sharing_policy_options
      allowed_repos = internal? ? "private or internal" : "private"

      if business_name.present?
        [
                {
                  value: :SHARING_POLICY_NONE,
                  text: "Not accessible",
                  description: "Workflows in other repositories cannot access this package."
                },
                {
                  value: :SHARING_POLICY_ACCESSIBLE_SAME_ORG,
                  text: "Accessible from repositories in the '#{owner_name}' organization",
                  description: "Workflows in other repositories that are part of the '#{owner_name}' organization can access this package. Access is allowed only from #{allowed_repos} repositories."
                },
                {
                  value: :SHARING_POLICY_ACCESSIBLE_SAME_BUSINESS,
                  text: "Accessible from repositories in the '#{business_name}' enterprise",
                  description: "Workflows in other repositories that are part of the '#{business_name}' enterprise can access this package. Access is allowed only from #{allowed_repos} repositories."
                }
        ]
      elsif is_owner_organization?
        [
                {
                  value: :SHARING_POLICY_NONE,
                  text: "Not accessible",
                  description: "Workflows in other repositories cannot access this package."
                },
                {
                  value: :SHARING_POLICY_ACCESSIBLE_SAME_ORG,
                  text: "Accessible from repositories in the '#{owner_name}' organization",
                  description: "Workflows in other repositories that are part of the '#{owner_name}' organization can access this package. Access is allowed only from #{allowed_repos} repositories."
                }
        ]
      else
        [
                {
                  value: :SHARING_POLICY_NONE,
                  text: "Not accessible",
                  description: "Workflows in other repositories cannot access this package."
                },
                {
                  value: :SHARING_POLICY_ACCESSIBLE_SAME_USER,
                  text: "Accessible from repositories owned by the user '#{owner_name}'",
                  description: "Workflows in other repositories that are owned by the user '#{owner_name}' can access this package. Access is allowed only from #{allowed_repos} repositories."
                }
        ]
      end
    end

    def internal?
      @package.internal?
    end

    def effective_policy
      @package.action_package_resolution_settings&.settings&.sharing_policy || :SHARING_POLICY_NONE
    end

    def owner_name
      @package.owner.display_login
    end

    def business_name
      @package.owner.business&.name || ""
    end

    def is_owner_organization?
      @package.owner.organization?
    end
  end
end
