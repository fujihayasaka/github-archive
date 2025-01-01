# typed: true
# frozen_string_literal: true

require "github/transitions/20231023221330_add_fgp_read_repo_metadata"

class AddFgpReadRepoMetadataTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddFgpReadRepoMetadata.new(arguments)
    transition.run
  end

  def self.down
  end
end
