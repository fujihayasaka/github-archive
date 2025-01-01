# typed: true
# frozen_string_literal: true

require "github/transitions/20240130174550_add_fgp_write_organization_actions_settings"

class AddFgpWriteOrganizationActionsSettingsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddFgpWriteOrganizationActionsSettings.new(arguments)
    transition.run
  end

  def self.down
  end
end
