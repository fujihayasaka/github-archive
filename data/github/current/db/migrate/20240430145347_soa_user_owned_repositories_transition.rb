# typed: true
# frozen_string_literal: true

require "github/transitions/20240430145347_soa_user_owned_repositories"

class SoaUserOwnedRepositoriesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::SoaUserOwnedRepositories.new(arguments)
    transition.run
  end

  def self.down
  end
end
