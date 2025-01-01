# typed: true
# frozen_string_literal: true

require "github/transitions/20240826200921_backfill_integration_visibility"

class BackfillIntegrationVisibilityTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillIntegrationVisibility.new(arguments)
    transition.run
  end

  def self.down
  end
end
