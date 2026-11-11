# typed: true
# frozen_string_literal: true

require "github/transitions/20231124095149_move_repo_merge_settings_from_kv_to_configuration"

class MoveRepoMergeSettingsFromKvToConfigurationTransition < ActiveRecord::Migration[7.2]
  def self.up
    return unless GitHub.enterprise?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveRepoMergeSettingsFromKvToConfiguration.new(arguments)
    transition.run
  end

  def self.down
  end
end
