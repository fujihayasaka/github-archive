# typed: true
# frozen_string_literal: true

module Permissions
  class ActionGrants
    GRANTS_BY_ACTION = {
      manage_all_apps: Granters::ManageAllApps,
      manage_app: Granters::ManageApp,
    }.freeze

    def self.lookup(action:)
      ActionGrants::GRANTS_BY_ACTION.fetch(action, Granter::Noop)
    end
  end
end
