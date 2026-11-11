# typed: true
# frozen_string_literal: true

require "github/transitions/20240311113531_delete_repo_merge_settings_from_kv"

class DeleteRepoMergeSettingsFromKvTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::DeleteRepoMergeSettingsFromKv.new(arguments)
    transition.run
  end

  def self.down
  end
end
