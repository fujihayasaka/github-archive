# typed: true
# frozen_string_literal: true

require "github/transitions/20250814193937_populate_rva_search_index_updated_at"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class PopulateRvaSearchIndexUpdatedAtTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::PopulateRvaSearchIndexUpdatedAt.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
