# typed: true
# frozen_string_literal: true

require "github/transitions/20250127121011_convert_enterprise_tag_protections"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class ConvertEnterpriseTagProtectionsTransition < ActiveRecord::Migration[8.0]
  def self.up
    return unless GitHub.enterprise? || Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)
    transition.run
  end

  def self.down
    # Migrations of tag protections cannot be undone
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
