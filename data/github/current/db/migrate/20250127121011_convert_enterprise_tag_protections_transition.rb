# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class ConvertEnterpriseTagProtectionsTransition < ActiveRecord::Migration[8.0]
  # This no longer does anything except add 20250127121011 to db/structure.sql.
  # All tag protections were migrated >2 GHES versions ago.

  def self.up
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
