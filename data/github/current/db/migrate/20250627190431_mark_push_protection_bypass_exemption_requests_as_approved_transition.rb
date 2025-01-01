# typed: true
# frozen_string_literal: true

require "github/transitions/20250627190431_mark_push_protection_bypass_exemption_requests_as_approved"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class MarkPushProtectionBypassExemptionRequestsAsApprovedTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MarkPushProtectionBypassExemptionRequestsAsApproved.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
