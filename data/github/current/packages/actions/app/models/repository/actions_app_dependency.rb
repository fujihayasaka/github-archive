# typed: true
# frozen_string_literal: true
# Actions App specific functionality for repositories
module Repository::ActionsAppDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  def enable_actions_app(actor: nil, entry_point:)
    app_installer = Actions::AppInstaller.new(T.cast(self, Repository)) # rubocop:todo GitHub/AvoidCast
    app_installer.enable_actions_app(actor: actor, entry_point: entry_point)
  end
end
