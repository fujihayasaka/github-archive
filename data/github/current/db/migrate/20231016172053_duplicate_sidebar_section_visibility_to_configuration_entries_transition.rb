# typed: true
# frozen_string_literal: true

require "github/transitions/20231016172053_duplicate_sidebar_section_visibility_to_configuration_entries"

class DuplicateSidebarSectionVisibilityToConfigurationEntriesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::DuplicateSidebarSectionVisibilityToConfigurationEntries.new(arguments)
    transition.run
  end

  def self.down
  end
end
