# typed: true
# frozen_string_literal: true

require "github/transitions/20250527104938_add_org_bypass_code_scanning_closure_requests_to_security_managers"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class AddOrgBypassCodeScanningClosureRequestsToSecurityManagersTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddOrgBypassCodeScanningClosureRequestsToSecurityManagers.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
