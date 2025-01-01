# typed: true
# frozen_string_literal: true

module Permissions
  class ActionEnumerators
    ENUMERATORS_BY_ACTION = {
      own_organization: Enumerators::OwnOrganization,
      manage_all_apps: Enumerators::ManageAllApps,
      grantable_manage_organization_apps: Enumerators::GrantableManageOrganizationApps,
      grantable_manage_app: Enumerators::GrantableManageApp,
      manage_app: Enumerators::ManageApp,
    }.freeze

    def self.lookup(action:)
      ENUMERATORS_BY_ACTION.fetch(action, Enumerators::Noop)
    end
  end
end
