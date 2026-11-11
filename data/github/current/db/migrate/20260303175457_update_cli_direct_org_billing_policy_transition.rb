# typed: true
# frozen_string_literal: true

require "github/transitions/20260303175457_update_cli_direct_org_billing_policy"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class UpdateCliDirectOrgBillingPolicyTransition < ActiveRecord::Migration[8.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::UpdateCliDirectOrgBillingPolicy.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
