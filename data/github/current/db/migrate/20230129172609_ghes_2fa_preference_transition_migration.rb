# typed: true

require "github/transitions/20230113154052_populate_2fa_preference_from_authenticated_devices"

class Ghes2faPreferenceTransitionMigration < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    transition = GitHub::Transitions::Populate2FaPreferenceFromAuthenticatedDevices.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
