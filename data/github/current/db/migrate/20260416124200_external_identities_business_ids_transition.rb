# typed: true
# frozen_string_literal: true

require "github/transitions/20260416124200_external_identities_business_ids"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class ExternalIdentitiesBusinessIdsTransition < ActiveRecord::Migration[8.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::ExternalIdentitiesBusinessIds.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
