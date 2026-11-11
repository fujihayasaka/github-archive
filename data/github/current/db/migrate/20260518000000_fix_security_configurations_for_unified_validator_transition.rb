# typed: true
# frozen_string_literal: true

require "github/transitions/20260518000000_fix_security_configurations_for_unified_validator"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class FixSecurityConfigurationsForUnifiedValidatorTransition < ActiveRecord::Migration[8.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::FixSecurityConfigurationsForUnifiedValidator.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
